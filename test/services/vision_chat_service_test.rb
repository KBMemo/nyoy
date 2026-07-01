# frozen_string_literal: true

require "base64"
require "test_helper"

class VisionChatServiceTest < ActiveSupport::TestCase
  PNG = Base64.decode64(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
  )

  FakeClient = Struct.new(:response, :captured, keyword_init: true) do
    def initialize(**)
      super(response: nil, captured: nil, **)
      self.captured ||= {}
    end

    def chat(**kwargs)
      self.captured = kwargs
      response
    end
  end

  test "analyze sends image and prompt to vision llama client" do
    large = Vips::Image.black(2000, 1000).pngsave_buffer
    client = FakeClient.new(
      response: { "choices" => [{ "message" => { "content" => "a red pixel" } }] }
    )

    service = VisionChatService.new(client: client)
    result = service.analyze(image: large, mime_type: "image/png", prompt: "describe this")

    assert_equal "a red pixel", result
    sent_image = Base64.decode64(client.captured[:messages].dig(0, :content).dig(0, :image_url, :url).sub(/\Adata:image\/\w+;base64,/, ""))
    dimensions = Vips::Image.new_from_buffer(sent_image, "")
    assert_equal 1024, [dimensions.width, dimensions.height].max
    content = client.captured[:messages].dig(0, :content)
    assert_equal 2, content.length
    assert content[0][:image_url][:url].start_with?("data:image/png;base64,")
    assert_equal "describe this", content[1][:text]
    assert_equal 0.2, client.captured[:temperature]
  end

  test "analyze raises when prompt is blank" do
    service = VisionChatService.new(client: FakeClient.new)

    assert_raises(VisionChatService::Error, match: /プロンプト/) do
      service.analyze(image: PNG, mime_type: "image/png", prompt: "  ")
    end
  end

  test "analyze raises when response is empty" do
    client = FakeClient.new(
      response: { "choices" => [{ "message" => { "content" => "" } }] }
    )
    service = VisionChatService.new(client: client)

    assert_raises(VisionChatService::Error, match: /空/) do
      service.analyze(image: PNG, mime_type: "image/png", prompt: "describe")
    end
  end
end
