# frozen_string_literal: true

class ChatMemoRagInjector
  class << self
    # Injects memo RAG into the latest user message so the conversation prefix
    # stays stable for llama.cpp prompt cache reuse.
    def apply!(llm_chat, query:, chat: nil)
      return llm_chat unless enabled?
      return llm_chat if query.blank?

      analysis = MemoRagQueryAnalyzer.analyze(query)
      chunks = MemoKnowledgeRetriever.new(limit: analysis.top_k).retrieve(query, keywords: analysis.keywords)
      compressed = MemoKnowledgeChunkCompressor.new.compress(chunks, query: query)
      formatter = chat ? MemoKnowledgeFormatter.for_chat(chat) : MemoKnowledgeFormatter.new
      context = formatter.format(compressed)
      return llm_chat if context.blank?

      attach_to_latest_user!(llm_chat, context)
      llm_chat
    end

    def enabled?
      Rails.application.config.x.nyoy.memo_rag_enabled &&
        NyoyConnectionStore.enabled?(:kbmemo) &&
        NyoyConnectionStore.api_token(:kbmemo).present?
    end

    private

    def attach_to_latest_user!(llm_chat, context)
      message = llm_chat.messages.reverse_each.find { |item| item.role.to_s == "user" }
      return llm_chat unless message

      body = message.content.to_s
      return llm_chat if body.include?(context)

      message.content = "#{context}\n\n#{body}".strip
      llm_chat
    end
  end
end
