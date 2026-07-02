# frozen_string_literal: true

class ChatMemoRagInjector
  class << self
    def apply!(llm_chat, query:, chat: nil)
      return llm_chat unless enabled?
      return llm_chat if query.blank?

      analysis = MemoRagQueryAnalyzer.analyze(query)
      chunks = MemoKnowledgeRetriever.new(limit: analysis.top_k).retrieve(query, keywords: analysis.keywords)
      compressed = MemoKnowledgeChunkCompressor.new.compress(chunks, query: query)
      formatter = chat ? MemoKnowledgeFormatter.for_chat(chat) : MemoKnowledgeFormatter.new
      context = formatter.format(compressed)
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
