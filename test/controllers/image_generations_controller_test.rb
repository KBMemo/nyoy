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

  test "translate_prompt returns translated prompt" do
    original = SdPromptTranslator.instance_method(:translate)
    SdPromptTranslator.define_method(:translate) { |*_args, **_kwargs| "chojugiga, rabbit" }

    post translate_prompt_image_generations_path,
      params: { japanese_prompt: "ウサギ" }.to_json,
      headers: @headers

    assert_response :success
    assert_equal "chojugiga, rabbit", response.parsed_body["prompt"]
  ensure
    SdPromptTranslator.define_method(:translate, original)
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
