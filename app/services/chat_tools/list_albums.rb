# frozen_string_literal: true

module ChatTools
  class ListAlbums < RubyLLM::Tool
    description "葛籠（tsuzura）のアルバム一覧を取得する。メディアの保存先を選ぶときに使う。"

    def name
      "list_albums"
    end

    def execute
      response = client.list_albums
      { albums: response.fetch("albums", []) }
    rescue TsuzuraClient::Error => e
      { error: e.message }
    end

    private

    def client
      @client ||= Registry.tsuzura_client
    end
  end
end
