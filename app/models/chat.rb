# frozen_string_literal: true

class Chat < ApplicationRecord
  acts_as_chat

  def assume_model_exists
    true
  end

  def to_llm
    self.context = ChatModelCatalog.context_for(model_association)
    @chat = nil

    model_record = model_association
    @chat ||= (context || RubyLLM).chat(
      model: model_record.model_id,
      provider: model_record.provider.to_sym,
      assume_model_exists: assume_model_exists || false
    )
    @chat.reset_messages!

    context = ChatContextBuilder.build(self)
    order_messages_for_llm(context.messages).each do |message|
      @chat.add_message(message.to_llm)
    end
    reapply_runtime_instructions(@chat)
    inject_conversation_summary!(@chat, context.summary)
    setup_persistence_callbacks

    ChatMemoRagInjector.apply!(@chat, query: latest_user_query(context.messages), chat: self)
    ChatTools::Registry.apply!(@chat)
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

    llm_chat.with_instructions("以前の会話の要約:\n#{trimmed}", append: true)
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
