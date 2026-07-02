# frozen_string_literal: true

class ChatMemoRagInjector
  class << self
    def apply!(llm_chat, query:)
      return llm_chat unless enabled?
      return llm_chat if query.blank?

      chunks = MemoKnowledgeRetriever.new.retrieve(query)
      context = MemoKnowledgeFormatter.new.format(chunks)
      return llm_chat if context.blank?

      llm_chat.with_instructions(context, append: true)
    end

    def enabled?
      Rails.application.config.x.nyoy.memo_rag_enabled &&
        NyoyConnectionStore.enabled?(:kbmemo) &&
        NyoyConnectionStore.api_token(:kbmemo).present?
    end
  end
end
