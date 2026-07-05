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
    assert_equal "illustrious_pencil-XL", generation.sd_model
    assert_includes generation.prompt, "rabbit and frog wrestling"
    assert_includes generation.resolved_negative_prompt, "busy background"
    assert_equal 2, generation.drafts.count
    assert_equal 2, captured[:batch_size]
    assert_equal "chojugiga/ChojuGiga_Illustrious.safetensors", captured[:lora].first["path"]
  ensure
    originals&.each { |klass, meth| klass.singleton_class.send(:define_method, :new, meth) }
  end

  test "user aspect_ratio overrides LLM plan" do
    generation = ImageGeneration.create!(
      japanese_prompt: "ウサギとカエルが相撲",
      style_id: "chojugiga_emaki",
      aspect_ratio: "square",
      draft_batch_size: 2
    )

    plan = StylePlanGenerator::Plan.new(
      style_id: "chojugiga_emaki",
      subject_prompt: "rabbit and frog wrestling",
      negative_extra: "",
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
    assert_equal "square", generation.aspect_ratio
    assert_equal 768, generation.width
    assert_equal 768, generation.height
    assert_equal 512, captured[:width]
    assert_equal 512, captured[:height]
  ensure
    originals&.each { |klass, meth| klass.singleton_class.send(:define_method, :new, meth) }
  end

  test "user negative_prompt overrides LLM negative_extra" do
    generation = ImageGeneration.create!(
      japanese_prompt: "ウサギ",
      style_id: "chojugiga_emaki",
      negative_prompt: "user negative",
      draft_batch_size: 2
    )

    plan = StylePlanGenerator::Plan.new(
      style_id: "chojugiga_emaki",
      subject_prompt: "rabbit",
      negative_extra: "llm negative",
      aspect_ratio: "square",
      source_chunk_ids: [],
      raw_response: "{}"
    )
    planner = Object.new
    planner.define_singleton_method(:call) { |*_, **_| plan }

    switcher = Class.new { def switch(*) = true }
    client = Class.new { def txt2img(**_) = %w[a b] }

    originals = { StylePlanGenerator => StylePlanGenerator.method(:new) }
    StylePlanGenerator.define_singleton_method(:new) { |**_| planner }

    with_generation_stubs(switcher:, client:) do
      GenerateImageJob.perform_now(generation.id)
    end

    generation.reload
    assert_equal "user negative", generation.negative_prompt
    assert_equal "photorealistic, 3d, colorful, user negative", generation.resolved_negative_prompt
  ensure
    originals&.each { |klass, meth| klass.singleton_class.send(:define_method, :new, meth) }
  end
end
