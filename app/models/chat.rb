# frozen_string_literal: true

class Chat < ApplicationRecord
  acts_as_chat

  # Wall-clock time spent building the LLM request in #to_llm (RAG + summary +
  # /props etc.), in ms. Read by ChatResponseJob to attribute TTFT to prework.
  attr_reader :context_build_elapsed_ms

  def assume_model_exists
    true
  end

  def to_llm
    build_started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    self.context = ChatModelCatalog.context_for(model_association)
    @chat = nil

    model_record = model_association
    @chat ||= (context || RubyLLM).chat(
      model: model_record.model_id,
      provider: model_record.provider.to_sym,
      assume_model_exists: assume_model_exists || false
    )
    @chat.reset_messages!

    # Keep the whole prompt prefix stable so llama.cpp can reuse the KV cache.
    # Tools/system instructions come first, then history. Both the rolling
    # summary and the per-turn RAG context are attached to the latest user
    # message (never the system prefix), so a growing conversation does not
    # invalidate the cached prefix every turn.
    ChatTools::Registry.apply!(@chat, chat: self)

    context = ChatContextBuilder.build(self)
    order_messages_for_llm(context.messages).each do |message|
      @chat.add_message(message.to_llm)
    end
    reapply_runtime_instructions(@chat)
    inject_conversation_summary!(@chat, context.summary)
    ChatMemoRagInjector.apply!(@chat, query: latest_user_query(context.messages), chat: self)
    ChatLlamaCache.apply!(@chat, chat: self)
    setup_persistence_callbacks

    @context_build_elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - build_started_at) * 1000).round
    @chat
  end

  private

  def inject_conversation_summary!(llm_chat, summary)
    return if summary.blank?

    trimmed = ChatContextBudget.trim_text(
      summary,
      max_tokens: ChatContextBudget.allocate(self).summary_tokens
    )
    return if trimmed.blank?

    prepend_to_latest_user!(llm_chat, "以前の会話の要約:\n#{trimmed}")
  end

  # Prepends context to the latest user message instead of the system prefix,
  # so the cached conversation prefix stays byte-identical across turns.
  def prepend_to_latest_user!(llm_chat, text)
    message = llm_chat.messages.reverse_each.find { |item| item.role.to_s == "user" }
    return unless message

    body = message.content.to_s
    return if body.include?(text)

    message.content = "#{text}\n\n#{body}".strip
  end

  def latest_user_query(messages)
    messages.reverse_each do |message|
      next unless message.role.to_s == "user"

      content = message.content.to_s.strip
      return content if content.present?
    end

    nil
  end
end
