# frozen_string_literal: true

module ChatTools
  class UpdateMemo < RubyLLM::Tool
    description "既存メモを更新する。get_memo で取得した updated_at を必ず渡す。末尾追記は append_body を使う。"

    def initialize(chat: nil)
      @chat = chat
    end

    def name
      "update_memo"
    end

    param :memo_ref, desc: "メモの uid（ULID）または数値 id", required: true
    param :updated_at, desc: "get_memo で取得した updated_at（ISO 8601）", required: true
    param :body, desc: "置き換える Markdown 本文（append_body と同時指定不可）", required: false
    param :append_body, desc: "本文末尾に追記する Markdown", required: false
    param :title, desc: "新しいタイトル", required: false

    def execute(memo_ref:, updated_at:, body: nil, append_body: nil, title: nil)
      if body.present? && append_body.present?
        return { error: "body と append_body は同時に指定できません" }
      end

      memo = client.update_memo(
        memo_ref,
        updated_at: updated_at,
        title: title,
        body: body,
        append_body: append_body
      )
      ChatMemoMediaInserter.append_media_to_memo!(client, @chat, memo)
    rescue TsurezureClient::Error => e
      { error: e.message }
    end

    private

    def client
      @client ||= Registry.client
    end
  end
end
