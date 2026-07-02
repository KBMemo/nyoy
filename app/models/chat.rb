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

    limited_messages = ChatContextLimiter.trim(
      messages_association.to_a,
      max_turns: Rails.application.config.x.nyoy.chat_context_turns
    )
    order_messages_for_llm(limited_messages).each do |message|
      @chat.add_message(message.to_llm)
    end
    reapply_runtime_instructions(@chat)
    setup_persistence_callbacks

    ChatMemoRagInjector.apply!(@chat, query: latest_user_query(limited_messages))
    ChatTools::Registry.apply!(@chat)
    @chat
  end

  private

  def latest_user_query(messages)
    messages.reverse_each do |message|
      next unless message.role.to_s == "user"

      content = message.content.to_s.strip
      return content if content.present?
    end

    nil
  end
end
