# frozen_string_literal: true

require "test_helper"

class ImageGenerationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @headers = { "ACCEPT" => "application/json", "CONTENT_TYPE" => "application/json" }
  end

  test "translate_prompt returns error when japanese prompt is blank" do
    post translate_prompt_image_generations_path,
      params: { japanese_prompt: "  " }.to_json,
      headers: @headers

    assert_response :unprocessable_entity
    assert_equal "日本語プロンプトを入力してください", response.parsed_body["error"]
  end

  test "generate_prompt_direct returns error when japanese prompt is blank" do
    post generate_prompt_direct_image_generations_path,
      params: { japanese_prompt: "  ", sd_model_profile_id: sd_model_profiles(:pony).id }.to_json,
      headers: @headers

    assert_response :unprocessable_entity
    assert_equal "日本語プロンプトを入力してください", response.parsed_body["error"]
  end

  test "generate_prompt_direct returns error when model is missing" do
    post generate_prompt_direct_image_generations_path,
      params: { japanese_prompt: "テスト" }.to_json,
      headers: @headers

    assert_response :unprocessable_entity
    assert_equal "画像生成モデルを選択してください", response.parsed_body["error"]
  end

  test "generate_prompt_direct returns prompt pair from direct generator" do
    profile = sd_model_profiles(:pony)
    generator = Object.new
    generator.define_singleton_method(:generate) do |japanese_prompt, sd_model_profile:, sd_prompt_template: nil|
      { prompt: "1girl, masterpiece", negative_prompt: "low quality", sd_prompt_template_id: 1 }
    end

    original = DirectPromptGenerator.method(:new)
    DirectPromptGenerator.define_singleton_method(:new) { |**| generator }

    post generate_prompt_direct_image_generations_path,
      params: { japanese_prompt: "少女", sd_model_profile_id: profile.id }.to_json,
      headers: @headers

    assert_response :success
    body = response.parsed_body
    assert_equal "1girl, masterpiece", body["prompt"]
    assert_equal "low quality", body["negative_prompt"]
    assert_equal 1, body["sd_prompt_template_id"]
  ensure
    DirectPromptGenerator.singleton_class.send(:define_method, :new, original)
  end

  test "create stores aspect_ratio and enqueues job" do
    assert_enqueued_with(job: GenerateImageJob) do
      post image_generations_path, params: {
        image_generation: {
          japanese_prompt: "ウサギ",
          style_id: "chojugiga_emaki",
          aspect_ratio: "landscape",
          draft_batch_size: 2
        }
      }
    end

    generation = ImageGeneration.order(:id).last
    assert_equal "landscape", generation.aspect_ratio
    assert_redirected_to image_generation_path(generation)
  end

  test "translate_prompt returns resolved prompt from style plan" do
    plan = StylePlanGenerator::Plan.new(
      style_id: "chojugiga_emaki",
      subject_prompt: "rabbit and frog",
      negative_extra: "low quality",
      aspect_ratio: "square",
      source_chunk_ids: [],
      raw_response: "{}"
    )
    planner = Object.new
    planner.define_singleton_method(:call) { |*_, **_| plan }

    original = StylePlanGenerator.method(:new)
    StylePlanGenerator.define_singleton_method(:new) { |**_| planner }

    post translate_prompt_image_generations_path,
      params: { japanese_prompt: "ウサギ", style_id: "chojugiga_emaki" }.to_json,
      headers: @headers

    assert_response :success
    body = response.parsed_body
    assert_includes body["prompt"], "chojugiga"
    assert_includes body["prompt"], "rabbit and frog"
    assert_equal "low quality", body["negative_prompt"]
  ensure
    StylePlanGenerator.singleton_class.send(:define_method, :new, original)
  end

  test "refine enqueues job when draft is selected" do
    generation = create_generation_awaiting_selection(draft_count: 2)

    assert_enqueued_with(job: RefineImageJob, args: [generation.id]) do
      post refine_image_generation_path(generation), params: { draft_index: 1, refine_denoising_strength: 0.45 }
    end

    assert_redirected_to image_generation_path(generation)
    generation.reload
    assert_equal "refining", generation.status
    assert_equal 1, generation.selected_draft_index
    assert_in_delta 0.45, generation.refine_denoising_strength
    assert generation.image_started_at
  end

  test "refine rejects invalid draft index" do
    generation = create_generation_awaiting_selection(draft_count: 2)

    assert_no_enqueued_jobs only: RefineImageJob do
      post refine_image_generation_path(generation), params: { draft_index: 99 }
    end

    assert_redirected_to image_generation_path(generation)
  end

  test "refine from completed generation re-runs selected draft" do
    generation = create_generation_awaiting_selection(draft_count: 2)
    generation.update!(status: "completed", finished_at: Time.current, selected_draft_index: 0)

    assert_enqueued_with(job: RefineImageJob, args: [generation.id]) do
      post refine_image_generation_path(generation), params: { draft_index: 1 }
    end

    generation.reload
    assert_equal "refining", generation.status
    assert_equal 1, generation.selected_draft_index
    assert_nil generation.finished_at
  end

  test "refine rejects while generation is in progress" do
    generation = create_generation_awaiting_selection(draft_count: 2)
    generation.update!(status: "refining")

    assert_no_enqueued_jobs only: RefineImageJob do
      post refine_image_generation_path(generation), params: { draft_index: 0 }
    end

    assert_redirected_to image_generation_path(generation)
  end

  test "destroy deletes completed generation" do
    generation = create_generation_awaiting_selection(draft_count: 1)

    assert_difference "ImageGeneration.count", -1 do
      delete image_generation_path(generation)
    end

    assert_redirected_to image_generations_path
  end

  test "destroy rejects in progress generation" do
    generation = create_generation_awaiting_selection(draft_count: 1)
    generation.update!(status: "drafting")

    assert_no_difference "ImageGeneration.count" do
      delete image_generation_path(generation)
    end

    assert_redirected_to image_generations_path
  end

  test "index delete button includes turbo confirm" do
    create_generation_awaiting_selection(draft_count: 1)

    get image_generations_path

    assert_response :success
    assert_select "form.nyoy-card-delete-form[data-controller=?]", "confirm-delete"
    assert_select "form[data-confirm-delete-message-value=?]", "この画像生成を削除しますか？"
  end

  test "new shows draft and direct tabs" do
    get new_image_generation_path

    assert_response :success
    assert_select "button.nyoy-img2img-tab", count: 2
    assert_select "button.nyoy-img2img-tab[data-section='draft']", text: "ラフ→仕上げ"
    assert_select "button.nyoy-img2img-tab[data-section='direct']", text: "パラメータ指定"
    assert_select "h2", text: "ラフ生成"
  end

  test "new direct section shows model and template selects" do
    get new_image_generation_path(section: "direct")

    assert_response :success
    assert_select "select[name='sd_model_profile_id']"
    assert_select "select[name='sd_prompt_template_id']"
    assert_select "h2", text: "実行パラメータ"
    assert_select "h2", text: "Hires / 拡大", count: 0
  end

  private

  def create_generation_awaiting_selection(draft_count:)
    generation = ImageGeneration.create!(
      prompt: "chojugiga, rabbit",
      sd_model: "flat2d",
      loras: "[]",
      status: "awaiting_selection"
    )

    draft_count.times do |index|
      generation.drafts.attach(
        io: StringIO.new("draft-#{index}"),
        filename: "draft-#{index}.png",
        content_type: "image/png"
      )
    end

    generation
  end
end
