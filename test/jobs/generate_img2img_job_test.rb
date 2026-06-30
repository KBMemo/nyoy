# frozen_string_literal: true

require "base64"
require "test_helper"

class GenerateImg2imgJobTest < ActiveJob::TestCase
  PNG = Base64.decode64(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
  )

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

  test "plans prompt and runs img2img with source dimensions" do
    generation = Img2imgGeneration.new(
      japanese_prompt: "水彩画風に",
      prompt: "watercolor style",
      negative_prompt: "busy background",
      resolved_negative_prompt: "busy background",
      denoising_strength: 0.6,
      steps: 22,
      sampler_name: "euler_a",
      loras: "[]",
      sd_model: "placeholder",
      resolved_params: { "switch_key" => "placeholder" }
    )
    generation.source_image.attach(io: StringIO.new(PNG), filename: "source.png", content_type: "image/png")
    generation.save!

    planner = Object.new
    planner.define_singleton_method(:call) { |*_, **_| raise "should not plan when prompt transferred" }
    switcher = Class.new { def switch(*) = true }

    captured = {}
    client = Class.new do
      define_method(:img2img) do |**kwargs|
        kwargs.each { |k, v| captured[k] = v }
        "png-bytes"
      end
    end

    with_stubs(planner:, switcher:, client:) do
      GenerateImg2imgJob.perform_now(generation.id)
    end

    generation.reload
    assert_equal "completed", generation.status
    assert_equal 1, generation.width
    assert_equal 1, generation.height
    assert generation.image.attached?
    assert_in_delta 0.6, captured[:denoising_strength]
    assert_equal PNG, captured[:init_image]
  end

  test "runs inpaint when generation mode is inpaint" do
    generation = Img2imgGeneration.new(
      prompt: "fix",
      negative_prompt: "bad",
      resolved_negative_prompt: "bad",
      denoising_strength: 0.6,
      steps: 22,
      sampler_name: "euler_a",
      loras: "[]",
      sd_model: "placeholder",
      resolved_params: { "switch_key" => "placeholder" },
      generation_mode: "inpaint"
    )
    generation.source_image.attach(io: StringIO.new(PNG), filename: "source.png", content_type: "image/png")
    generation.mask_image.attach(io: StringIO.new(PNG), filename: "mask.png", content_type: "image/png")
    generation.save!

    planner = Object.new
    planner.define_singleton_method(:call) { |*_, **_| raise "should not plan" }
    switcher = Class.new { def switch(*) = true }

    captured = {}
    client = Class.new do
      define_method(:inpaint) do |**kwargs|
        kwargs.each { |k, v| captured[k] = v }
        "png-bytes"
      end

      define_method(:img2img) { |_| raise "should use inpaint" }
    end

    with_stubs(planner:, switcher:, client:) do
      GenerateImg2imgJob.perform_now(generation.id)
    end

    assert_equal PNG, captured[:mask]
    assert_equal PNG, captured[:init_image]
  end
end
