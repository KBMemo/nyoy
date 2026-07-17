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

  setup do
    ChatModelCatalog.seed!
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
    run = AgentRun.order(:id).last
    assert_select "#vision-result a[href='#{chat_agent_run_path(run.chat, run)}']", text: "AgentRun ##{run.id}"
    assert_equal AgentGraph::ImageUnderstandingGraph::NAME, run.graph_name
    assert_predicate run, :completed?
  ensure
    VisionChatService.singleton_class.send(:define_method, :new, original_new)
  end

  test "create returns json for fetch submissions" do
    file = Rack::Test::UploadedFile.new(StringIO.new(PNG), "image/png", original_filename: "sample.png")
    service = FakeService.new(result: "猫が写っています")

    original_new = VisionChatService.method(:new)
    VisionChatService.define_singleton_method(:new) { |**| service }

    post image_understandings_path,
         params: { image: file, prompt: "何が写っていますか？" },
         headers: { "Accept" => "application/json" }

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal "猫が写っています", json["result"]
    assert_equal "何が写っていますか？", json["prompt"]
    assert json["image_data_url"].start_with?("data:image/png;base64,")
    run = AgentRun.find(json["agent_run_id"])
    assert_predicate run, :completed?
    assert_equal chat_agent_run_path(run.chat, run), json["agent_run_path"]
  ensure
    VisionChatService.singleton_class.send(:define_method, :new, original_new)
  end

  test "create returns json error" do
    post image_understandings_path,
         params: { prompt: "説明して" },
         headers: { "Accept" => "application/json" }

    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert_equal "画像を選択してください", json["error"]
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
