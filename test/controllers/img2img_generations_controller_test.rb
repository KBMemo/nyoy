# frozen_string_literal: true

require "base64"
require "test_helper"

class Img2imgGenerationsControllerTest < ActionDispatch::IntegrationTest
  PNG = Base64.decode64(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
  )

  test "new renders form" do
    get new_img2img_generation_path
    assert_response :success
  end

  test "create enqueues job with uploaded source image" do
    file = Rack::Test::UploadedFile.new(StringIO.new(PNG), "image/png", original_filename: "source.png")

    assert_enqueued_with(job: GenerateImg2imgJob) do
      post img2img_generations_path, params: {
        img2img_generation: {
          japanese_prompt: "水彩画風に",
          prompt: "watercolor",
          negative_prompt: "bad",
          source_image: file,
          denoising_strength: 0.55,
          steps: 22,
          cfg_scale: 6.0,
          sampler_name: "euler_a",
          loras: "[]",
          sd_model: "test-model",
          generation_mode: "img2img"
        }
      }
    end

    generation = Img2imgGeneration.order(:created_at).last
    assert generation.source_image.attached?
    assert_equal "img2img", generation.generation_mode
    assert_redirected_to img2img_generation_path(generation)
  end

  test "new renders mode tabs" do
    get new_img2img_generation_path
    assert_response :success
    assert_select "button.nyoy-img2img-tab", count: 5
    assert_select "button.nyoy-img2img-tab[data-mode='sketch']", text: "Sketch"
  end

  test "create inpaint mode attaches mask from data url" do
    file = Rack::Test::UploadedFile.new(StringIO.new(PNG), "image/png", original_filename: "source.png")
    mask_data = "data:image/png;base64,#{Base64.strict_encode64(PNG)}"

    assert_enqueued_with(job: GenerateImg2imgJob) do
      post img2img_generations_path, params: {
        mask: mask_data,
        img2img_generation: {
          japanese_prompt: "修正",
          prompt: "fix area",
          negative_prompt: "bad",
          source_image: file,
          denoising_strength: 0.55,
          steps: 22,
          cfg_scale: 6.0,
          sampler_name: "euler_a",
          loras: "[]",
          sd_model: "test-model",
          generation_mode: "inpaint"
        }
      }
    end

    generation = Img2imgGeneration.order(:created_at).last
    assert_equal "inpaint", generation.generation_mode
    assert generation.mask_image.attached?
  end

  test "new transfers image and prompts from memo illustration" do
    illustration = MemoIllustration.create!(
      body: "転記テスト",
      status: "completed",
      positive_prompt: "test prompt",
      resolved_negative_prompt: "bad quality"
    )
    illustration.image.attach(io: StringIO.new(PNG), filename: "a.png", content_type: "image/png")

    get new_img2img_generation_path(from_memo: illustration.id)

    assert_response :success
    assert_select "textarea[name='img2img_generation[japanese_prompt]']", text: /転記テスト/
    assert_select "textarea[name='img2img_generation[prompt]']", text: /test prompt/
    assert_select "textarea[name='img2img_generation[negative_prompt]']", text: /bad quality/
  end

  test "create with transfer hidden fields does not assign them to model" do
    illustration = MemoIllustration.create!(
      body: "転記テスト",
      status: "completed",
      positive_prompt: "test prompt",
      resolved_negative_prompt: "bad quality",
      steps: 20,
      cfg_scale: 6.0,
      seed: 42,
      resolved_params: { "switch_key" => "test-model" },
      sd_model: "test-model"
    )
    illustration.image.attach(io: StringIO.new(PNG), filename: "a.png", content_type: "image/png")

    assert_enqueued_with(job: GenerateImg2imgJob) do
      post img2img_generations_path, params: {
        img2img_generation: {
          from_memo: illustration.id,
          japanese_prompt: "転記テスト",
          prompt: "test prompt",
          negative_prompt: "bad quality",
          denoising_strength: 0.55,
          steps: 20,
          cfg_scale: 6.0,
          seed: 42,
          sampler_name: "euler_a"
        }
      }
    end

    generation = Img2imgGeneration.order(:created_at).last
    assert generation.source_image.attached?
    assert_equal "test prompt", generation.prompt
    assert_equal 42, generation.seed
    assert_redirected_to img2img_generation_path(generation)
  end
end
