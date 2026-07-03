# frozen_string_literal: true

require "test_helper"

class GeneratedImageMemoSaverTest < ActiveSupport::TestCase
  setup do
    @generation = ImageGeneration.create!(
      japanese_prompt: "テスト猫",
      prompt: "test cat",
      sd_model: "test.safetensors",
      width: 512,
      height: 512,
      steps: 20,
      cfg_scale: 6.0,
      sampler_name: "euler_a",
      loras: "[]",
      status: "completed"
    )
    @generation.refined_images.attach(
      io: StringIO.new("png-bytes"),
      filename: "refined.png",
      content_type: "image/png",
      metadata: { sequence: 1, draft_index: 0 }
    )
    @attachment = @generation.refined_images.attachments.last
  end

  test "available? requires kbmemo and tsuzura tokens" do
    kbmemo = service_connections(:kbmemo)
    tsuzura = service_connections(:tsuzura)
    original_kbmemo = kbmemo.api_token
    original_tsuzura = tsuzura.api_token

    kbmemo.update!(api_token: "kbmemo_test", enabled: true)
    tsuzura.update!(api_token: "tsuzura_test", enabled: true)
    assert GeneratedImageMemoSaver.available?

    kbmemo.update!(api_token: nil)
    assert_not GeneratedImageMemoSaver.available?
  ensure
    kbmemo.update!(api_token: original_kbmemo) if defined?(kbmemo)
    tsuzura.update!(api_token: original_tsuzura) if defined?(tsuzura)
  end

  test "uploads image creates memo and appends media macro" do
    calls = []
    fake_tsuzura = Object.new
    fake_tsuzura.define_singleton_method(:configured?) { true }
    fake_tsuzura.define_singleton_method(:upload_batch) do |**|
      calls << :upload
      { "items" => [{ "id" => "01JMEDIA" }] }
    end

    fake_tsurezure = Object.new
    fake_tsurezure.define_singleton_method(:configured?) { true }
    fake_tsurezure.define_singleton_method(:create_memo) do |**|
      calls << :create
      { "uid" => "01JMEMO", "updated_at" => "2026-07-03T10:00:00Z", "url" => "https://kbmemo.net/memos/01JMEMO" }
    end
    fake_tsurezure.define_singleton_method(:update_memo) do |memo_ref, **kwargs|
      calls << [:update, memo_ref, kwargs]
      { "uid" => memo_ref, "url" => "https://kbmemo.net/memos/01JMEMO" }
    end

    result = GeneratedImageMemoSaver.call(
      attachment: @attachment,
      tsuzura_client: fake_tsuzura,
      tsurezure_client: fake_tsurezure
    )

    assert_equal %i[upload create], calls[0..1]
    assert_equal "01JMEMO", calls.last[1]
    assert_equal "image::media:01JMEDIA[]", calls.last[2][:append_body]
    assert_equal "01JMEDIA", @attachment.reload.metadata["tsuzura_media_id"]
    assert_equal ["01JMEDIA"], result["appended_media_ids"]
  end

  test "reuses existing tsuzura_media_id on attachment" do
    @attachment.update!(metadata: { tsuzura_media_id: "01JEXISTING" })

    fake_tsuzura = Object.new
    fake_tsuzura.define_singleton_method(:configured?) { true }
    fake_tsuzura.define_singleton_method(:upload_batch) { raise "should not upload" }

    fake_tsurezure = Object.new
    fake_tsurezure.define_singleton_method(:configured?) { true }
    fake_tsurezure.define_singleton_method(:create_memo) do |**|
      { "uid" => "01JMEMO", "updated_at" => "2026-07-03T10:00:00Z" }
    end
    fake_tsurezure.define_singleton_method(:update_memo) do |memo_ref, **kwargs|
      { "uid" => memo_ref, "appended_media_ids" => ["01JEXISTING"] }
    end

    result = GeneratedImageMemoSaver.call(
      attachment: @attachment,
      tsuzura_client: fake_tsuzura,
      tsurezure_client: fake_tsurezure
    )

    assert_equal ["01JEXISTING"], result["appended_media_ids"]
  end
end
