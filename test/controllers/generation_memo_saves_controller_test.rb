# frozen_string_literal: true

require "test_helper"

class GenerationMemoSavesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @generation = ImageGeneration.create!(
      japanese_prompt: "保存テスト",
      prompt: "save test",
      sd_model: "test.safetensors",
      width: 512,
      height: 512,
      steps: 20,
      cfg_scale: 6.0,
      sampler_name: "euler_a",
      loras: "[]",
      status: "completed"
    )
    @generation.image.attach(
      io: StringIO.new("png"),
      filename: "result.png",
      content_type: "image/png"
    )
    @attachment = @generation.image_attachment

    service_connections(:kbmemo).update!(api_token: "kbmemo_test", enabled: true)
    service_connections(:tsuzura).update!(api_token: "tsuzura_test", enabled: true)
  end

  test "create saves attachment to kbmemo memo" do
    result = { "url" => "https://kbmemo.net/memos/01JMEMO" }
    original = GeneratedImageMemoSaver.method(:call)
    GeneratedImageMemoSaver.define_singleton_method(:call) { |**| result }

    post generation_memo_saves_path, params: { attachment_id: @attachment.id }

    assert_redirected_to "https://kbmemo.net/memos/01JMEMO"
    assert_equal "徒然に保存しました", flash[:notice]
  ensure
    GeneratedImageMemoSaver.define_singleton_method(:call, original) if defined?(original)
  end

  test "create rejects unknown attachment" do
    post generation_memo_saves_path, params: { attachment_id: 0 }

    assert_redirected_to root_path
    assert_equal "保存できない画像です", flash[:alert]
  end
end
