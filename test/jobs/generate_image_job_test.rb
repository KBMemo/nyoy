# frozen_string_literal: true

require "test_helper"

module ImageGenerationJobTestHelper
  def with_generation_stubs(switcher:, client:)
    original_switcher_new = SdModelSwitcher.method(:new)
    original_client_new = SdCppClient.method(:new)

    SdModelSwitcher.define_singleton_method(:new) { switcher.new }
    SdCppClient.define_singleton_method(:new) { client.new }
    yield
  ensure
    SdModelSwitcher.singleton_class.send(:define_method, :new, original_switcher_new)
    SdCppClient.singleton_class.send(:define_method, :new, original_client_new)
  end

  def with_image_resizer_stub(return_value: "resized-bytes")
    original = ImageResizer.method(:resize_png)
    ImageResizer.define_singleton_method(:resize_png) { |*_| return_value }
    yield
  ensure
    ImageResizer.singleton_class.send(:define_method, :resize_png, original)
  end
end

class GenerateImageJobTest < ActiveJob::TestCase
  include ImageGenerationJobTestHelper

  test "generates drafts and waits for selection" do
    generation = ImageGeneration.create!(
      prompt: "chojugiga, rabbit",
      sd_model: "flat2d",
      loras: "[]",
      draft_batch_size: 2
    )

    switcher = Class.new do
      def switch(*); true; end
    end

    client = Class.new do
      def txt2img(**kwargs)
        raise "unexpected batch size" unless kwargs[:batch_size] == 2

        %w[draft-a draft-b]
      end
    end

    with_generation_stubs(switcher:, client:) do
      GenerateImageJob.perform_now(generation.id)
    end

    generation.reload
    assert_equal "awaiting_selection", generation.status
    assert_equal 2, generation.drafts.count
    assert_not generation.image.attached?
  end
end

class RefineImageJobTest < ActiveJob::TestCase
  include ImageGenerationJobTestHelper

  test "refines selected draft and upscales with hires" do
    generation = ImageGeneration.create!(
      prompt: "chojugiga, rabbit",
      sd_model: "flat2d",
      loras: "[]",
      width: 512,
      height: 512,
      status: "awaiting_selection",
      selected_draft_index: 0,
      refine_denoising_strength: 0.4,
      enable_hires: true,
      hires_scale: 1.5
    )
    generation.drafts.attach(
      io: StringIO.new("draft-bytes"),
      filename: "draft-0.png",
      content_type: "image/png"
    )

    switcher = Class.new do
      def switch(*); true; end
    end

    calls = []
    client = Class.new do
      define_method(:img2img) do |**kwargs|
        calls << kwargs
        calls.size == 1 ? "refined-bytes" : "final-bytes"
      end
    end

    with_generation_stubs(switcher:, client:) do
      RefineImageJob.perform_now(generation.id)
    end

    generation.reload
    assert_equal 2, calls.size
    assert_equal generation.draft_width, calls.first[:width]
    assert_equal generation.draft_height, calls.first[:height]
    assert_equal "draft-bytes", calls.first[:init_image]
    assert_in_delta 0.4, calls.first[:denoising_strength]
    assert_equal "refined-bytes", calls.second[:init_image]
    assert_equal generation.draft_width, calls.second[:width]
    assert_equal generation.draft_height, calls.second[:height]
    assert calls.second[:enable_hr]
    assert_equal 768, calls.second[:hr_resize_x]
    assert_equal 768, calls.second[:hr_resize_y]
    assert_equal "completed", generation.status
    assert_equal 1, generation.refined_images.count
    assert_equal "final-bytes", generation.refined_images.last.download
    assert_equal 0, generation.refined_images.last.metadata["draft_index"]
  end

  test "refines without hires when disabled" do
    generation = ImageGeneration.create!(
      prompt: "chojugiga, rabbit",
      sd_model: "flat2d",
      loras: "[]",
      width: 512,
      height: 512,
      status: "awaiting_selection",
      selected_draft_index: 0,
      refine_denoising_strength: 0.4,
      enable_hires: false
    )
    generation.drafts.attach(
      io: StringIO.new("draft-bytes"),
      filename: "draft-0.png",
      content_type: "image/png"
    )

    switcher = Class.new do
      def switch(*); true; end
    end

    calls = []
    client = Class.new do
      define_method(:img2img) do |**kwargs|
        calls << kwargs
        "refined-bytes"
      end
    end

    with_image_resizer_stub(return_value: "upscaled-bytes") do
      with_generation_stubs(switcher:, client:) do
        RefineImageJob.perform_now(generation.id)
      end
    end

    assert_equal 1, calls.size
    assert_equal generation.draft_width, calls.first[:width]
    assert_equal generation.draft_height, calls.first[:height]
    assert_equal 1, generation.reload.refined_images.count
    assert_equal "upscaled-bytes", generation.refined_images.last.download
  end

  test "keeps previous refined images when refining again" do
    generation = ImageGeneration.create!(
      prompt: "chojugiga, rabbit",
      sd_model: "flat2d",
      loras: "[]",
      status: "completed",
      selected_draft_index: 0,
      refine_denoising_strength: 0.4,
      enable_hires: false
    )
    generation.drafts.attach(io: StringIO.new("draft-0"), filename: "draft-0.png", content_type: "image/png")
    generation.drafts.attach(io: StringIO.new("draft-1"), filename: "draft-1.png", content_type: "image/png")
    generation.refined_images.attach(
      io: StringIO.new("first-result"),
      filename: "refined-1.png",
      content_type: "image/png",
      metadata: { draft_index: 0, sequence: 1 }
    )

    switcher = Class.new do
      def switch(*); true; end
    end

    client = Class.new do
      define_method(:img2img) { |**_| "second-result" }
    end

    generation.update!(selected_draft_index: 1)
    with_image_resizer_stub do
      with_generation_stubs(switcher:, client:) do
        RefineImageJob.perform_now(generation.id)
      end
    end

    generation.reload
    assert_equal 2, generation.refined_images.count
    assert_equal "first-result", generation.refined_images.attachments.order(:created_at).first.download
    assert_equal "resized-bytes", generation.refined_images.attachments.order(:created_at).last.download
  end
end
