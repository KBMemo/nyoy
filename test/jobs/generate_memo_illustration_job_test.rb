# frozen_string_literal: true

require "test_helper"

class GenerateMemoIllustrationJobTest < ActiveJob::TestCase
  def with_stubs(planner:, switcher:, client:)
    originals = {
      StylePlanGenerator => StylePlanGenerator.method(:new),
      SdModelSwitcher => SdModelSwitcher.method(:new),
      SdCppClient => SdCppClient.method(:new)
    }
    StylePlanGenerator.define_singleton_method(:new) { |**_| planner }
    SdModelSwitcher.define_singleton_method(:new) { switcher.new }
    SdCppClient.define_singleton_method(:new) { client.new }
    yield
  ensure
    originals.each do |klass, meth|
      klass.singleton_class.send(:define_method, :new, meth)
    end
  end

  test "plans via style, resolves payload, and attaches the image" do
    illustration = MemoIllustration.create!(body: "ウサギとカエルが相撲をとっている")

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
        "png-bytes"
      end
    end

    with_stubs(planner:, switcher:, client:) do
      GenerateMemoIllustrationJob.perform_now(illustration.id)
    end

    illustration.reload
    assert_equal "completed", illustration.status
    assert_equal "chojugiga_emaki", illustration.style_id
    assert_equal "illustrious_pencil-XL", illustration.sd_model
    assert_includes illustration.positive_prompt, "rabbit and frog wrestling"
    assert_includes illustration.resolved_negative_prompt, "busy background"
    assert_equal 1024, illustration.width
    assert_equal 768, illustration.height
    assert illustration.image.attached?

    # payload carried resolved loras from the style
    assert_equal "chojugiga/ChojuGiga_Illustrious.safetensors", captured[:lora].first["path"]
  end
end
