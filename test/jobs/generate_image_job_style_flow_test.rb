# frozen_string_literal: true

require "test_helper"

class GenerateImageJobStyleFlowTest < ActiveJob::TestCase
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

  test "plans via style, resolves payload, and generates drafts" do
    generation = ImageGeneration.create!(
      japanese_prompt: "ウサギとカエルが相撲",
      style_id: "chojugiga_emaki",
      draft_batch_size: 2
    )

    plan = StylePlanGenerator::Plan.new(
      style_id: "chojugiga_emaki",
      subject_prompt: "rabbit and frog wrestling",
      negative_extra: "busy background",
      aspect_ratio: "landscape",
      source_chunk_ids: [],
      raw_response: "{}"
    )
    planner = Object.new
    planner.define_singleton_method(:call) { |*_, **_| plan }

    switcher = Class.new { def switch(*) = true }

    captured = {}
    client = Class.new do
      define_method(:txt2img) do |**kwargs|
        kwargs.each { |k, v| captured[k] = v }
        %w[draft-a draft-b]
      end
    end

    originals = { StylePlanGenerator => StylePlanGenerator.method(:new) }
    StylePlanGenerator.define_singleton_method(:new) { |**_| planner }

    with_generation_stubs(switcher:, client:) do
      GenerateImageJob.perform_now(generation.id)
    end

    generation.reload
    assert_equal "awaiting_selection", generation.status
    assert_equal "chojugiga_emaki", generation.style_id
    assert_equal "pony-v6", generation.sd_model
    assert_includes generation.prompt, "rabbit and frog wrestling"
    assert_includes generation.resolved_negative_prompt, "busy background"
    assert_equal 2, generation.drafts.count
    assert_equal 2, captured[:batch_size]
    assert_equal "chojugiga/ChojuGiga_Illustrious.safetensors", captured[:lora].first["path"]
  ensure
    originals&.each { |klass, meth| klass.singleton_class.send(:define_method, :new, meth) }
  end
end
