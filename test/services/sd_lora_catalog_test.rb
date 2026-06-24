# frozen_string_literal: true

require "test_helper"

class SdLoraCatalogTest < ActiveSupport::TestCase
  FakeClient = Struct.new(:response, keyword_init: true) do
    def get_json(_path)
      response
    end
  end

  test "normalizes lora entries from sd-server" do
    client = FakeClient.new(
      response: [
        { "name" => "ChojuGiga_Illustrious", "path" => "chojugiga/ChojuGiga_Illustrious.safetensors" }
      ]
    )

    catalog = SdLoraCatalog.new(client: client)
    loras = catalog.list

    assert_equal 1, loras.size
    assert_equal "ChojuGiga_Illustrious", loras.first["name"]
    assert_equal "chojugiga/ChojuGiga_Illustrious.safetensors", loras.first["path"]
  end
end
