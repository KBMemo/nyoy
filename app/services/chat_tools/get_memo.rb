# frozen_string_literal: true

module ChatTools
  class GetMemo < RubyLLM::Tool
    description "徒然のメモを uid または数値 id で取得する。更新前に updated_at を確認するときにも使う。"

    def name
      "get_memo"
    end

    param :memo_ref, desc: "メモの uid（ULID）または数値 id", required: true

    def execute(memo_ref:)
      client.get_memo(memo_ref)
    rescue TsurezureClient::Error => e
      { error: e.message }
    end

    private

    def client
      @client ||= Registry.client
    end
  end
end
