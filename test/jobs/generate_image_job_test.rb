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

  test "refines selected draft into final image" do
    generation = ImageGeneration.create!(
      prompt: "chojugiga, rabbit",
      sd_model: "flat2d",
      loras: "[]",
      status: "awaiting_selection",
      selected_draft_index: 0,
      refine_denoising_strength: 0.4
    )
    generation.drafts.attach(
      io: StringIO.new("draft-bytes"),
      filename: "draft-0.png",
      content_type: "image/png"
    )

    switcher = Class.new do
      def switch(*); true; end
    end

    client = Class.new do
      def img2img(**kwargs)
        raise "unexpected init image" unless kwargs[:init_image] == "draft-bytes"
        raise "unexpected denoising strength" unless (kwargs[:denoising_strength] - 0.4).abs < 0.001

        "final-bytes"
      end
    end

    with_generation_stubs(switcher:, client:) do
      RefineImageJob.perform_now(generation.id)
    end

    generation.reload
    assert_equal "completed", generation.status
    assert generation.image.attached?
    assert_equal "final-bytes", generation.image.download
  end
end
