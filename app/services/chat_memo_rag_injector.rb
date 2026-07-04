# frozen_string_literal: true

class ChatMemoRagInjector
  DEFAULT_MODE = "tool"

  class << self
    # Injects memo RAG into the latest user message so the conversation prefix
    # stays stable for llama.cpp prompt cache reuse. Used only in :inject mode.
    def apply!(llm_chat, query:, chat: nil)
      return llm_chat unless enabled?
      return llm_chat if query.blank?

      context = context_for(query: query, chat: chat)
      return llm_chat if context.blank?

      attach_to_latest_user!(llm_chat, context)
      llm_chat
    end

    # Runs the hybrid (vector + keyword) memo RAG pipeline and returns the
    # formatted context string, or nil when nothing relevant is found. Shared by
    # the auto-injection path and the recall_memos tool.
    def context_for(query:, chat: nil)
      return nil if query.blank?

      analysis = MemoRagQueryAnalyzer.analyze(query)
      chunks = MemoKnowledgeRetriever.new(limit: analysis.top_k).retrieve(query, keywords: analysis.keywords)
      compressed = MemoKnowledgeChunkCompressor.new.compress(chunks, query: query)
      formatter = chat ? MemoKnowledgeFormatter.for_chat(chat) : MemoKnowledgeFormatter.new
      formatter.format(compressed)
    end

    def enabled?
      Rails.application.config.x.nyoy.memo_rag_enabled &&
        NyoyConnectionStore.enabled?(:kbmemo) &&
        NyoyConnectionStore.api_token(:kbmemo).present?
    end

    def mode
      Rails.application.config.x.nyoy.memo_rag_mode.to_s.presence || DEFAULT_MODE
    end

    # Auto-injects RAG context into every turn (higher recall, more prework).
    def inject_mode?
      enabled? && mode == "inject"
    end

    # Exposes RAG as the recall_memos tool the model calls on demand
    # (no per-turn prework, model decides when memory is needed).
    def tool_mode?
      enabled? && mode == "tool"
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
