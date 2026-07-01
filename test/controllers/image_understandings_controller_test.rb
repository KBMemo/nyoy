# frozen_string_literal: true

require "base64"
require "test_helper"

class ImageUnderstandingsControllerTest < ActionDispatch::IntegrationTest
  PNG = Base64.decode64(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
  )

  FakeService = Struct.new(:result, :captured, keyword_init: true) do
    def initialize(**)
      super(result: nil, captured: nil, **)
      self.captured ||= {}
    end

    def analyze(image:, mime_type:, prompt:)
      self.captured = { image: image, mime_type: mime_type, prompt: prompt }
      result
    end
  end

  test "new renders form" do
    get new_image_understanding_path
    assert_response :success
    assert_select "h1", text: "画像理解"
    assert_select "input[type=file][name=image]"
    assert_select "textarea[name=prompt]"
  end

  test "create shows result from vision service" do
    file = Rack::Test::UploadedFile.new(StringIO.new(PNG), "image/png", original_filename: "sample.png")
    service = FakeService.new(result: "猫が写っています")

    original_new = VisionChatService.method(:new)
    VisionChatService.define_singleton_method(:new) { |**| service }

    post image_understandings_path, params: { image: file, prompt: "何が写っていますか？" }

    assert_response :success
    assert_select "#vision-result p", text: "猫が写っています"
    assert_select "form[data-turbo='false']"
    assert_equal PNG, service.captured[:image]
    assert_equal "image/png", service.captured[:mime_type]
    assert_equal "何が写っていますか？", service.captured[:prompt]
  ensure
    VisionChatService.singleton_class.send(:define_method, :new, original_new)
  end

  test "create validates missing image" do
    post image_understandings_path, params: { prompt: "説明して" }
    assert_response :unprocessable_entity
  end

  test "create validates missing prompt" do
    file = Rack::Test::UploadedFile.new(StringIO.new(PNG), "image/png", original_filename: "sample.png")

    post image_understandings_path, params: { image: file, prompt: "  " }
    assert_response :unprocessable_entity
  end
end
