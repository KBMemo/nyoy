# frozen_string_literal: true

module ChatTools
  class CreateMemo < RubyLLM::Tool
    description "会話の内容を徒然に新規メモとして保存する。ユーザーが明示的に保存を求めたときのみ使う。本文は Markdown。"

    def name
      "create_memo"
    end

    param :body, desc: "メモ本文（Markdown）", required: true
    param :title, desc: "タイトル（省略時は徒然側で自動生成）", required: false
    param :tags, type: "array", desc: "タグ名の配列", required: false

    def execute(body:, title: nil, tags: nil)
      client.create_memo(title: title, body: body, tags: tags)
    rescue TsurezureClient::Error => e
      { error: e.message }
    end

    private

    def client
      @client ||= Registry.client
    end
  end
end
