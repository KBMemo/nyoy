# frozen_string_literal: true

module ChatTools
  # On-demand semantic recall of the user's past memos (徒然). Runs the same
  # hybrid vector + keyword RAG pipeline that used to be auto-injected every
  # turn, but only when the model decides it needs prior memo knowledge.
  class RecallMemos < RubyLLM::Tool
    description "自分の過去メモ（徒然）から質問に関連する知識を意味検索で呼び出す。過去に書いた内容・決定・記録を踏まえて答える必要があるときに使う。キーワードの厳密一致で一覧を探すだけなら search_memos。"

    def initialize(chat: nil)
      @chat = chat
    end

    def name
      "recall_memos"
    end

    param :query, desc: "思い出したい内容を表す自然文の質問またはキーワード", required: true

    def execute(query:)
      context = ChatMemoRagInjector.context_for(query: query, chat: @chat)
      return { context: nil, note: "関連するメモは見つかりませんでした。" } if context.blank?

      { context: ChatTools::ToolResponse.safe_string(context) }
    rescue StandardError => e
      { error: e.message }
    end
  end
end
