# frozen_string_literal: true

module ChatTools
  class GetMedia < RubyLLM::Tool
    description "葛籠に保存されたメディアのメタデータを取得する。ID は list_albums やアップロード結果から得る。"

    def name
      "get_media"
    end

    param :media_id, desc: "葛籠メディア ID（ULID）", required: true

    def execute(media_id:)
      item = client.get_media(media_id)
      { media: item }
    rescue TsuzuraClient::Error => e
      { error: e.message }
    end

    private

    def client
      @client ||= Registry.tsuzura_client
    end
  end
end
