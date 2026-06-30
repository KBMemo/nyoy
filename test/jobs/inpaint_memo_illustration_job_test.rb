# frozen_string_literal: true

require "test_helper"

class InpaintMemoIllustrationJobTest < ActiveJob::TestCase
  MINI_PNG = Base64.decode64(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
  ).freeze

  def with_stubs(switcher:, client:)
    originals = {
      SdModelSwitcher => SdModelSwitcher.method(:new),
      SdCppClient => SdCppClient.method(:new)
    }
    SdModelSwitcher.define_singleton_method(:new) { switcher.new }
    SdCppClient.define_singleton_method(:new) { client.new }
    yield
  ensure
    originals.each do |klass, meth|
      klass.singleton_class.send(:define_method, :new, meth)
    end
  end

  test "inpaints with delta prompt and optional style tags" do
    illustration = MemoIllustration.create!(
      body: "サッカーボール",
      status: "completed",
      style_id: prompt_styles(:chojugiga).style_id,
      positive_prompt: "girl holding soccer ball",
      resolved_negative_prompt: "bad hands",
      steps: 20,
      cfg_scale: 7.0,
      resolved_params: { "switch_key" => "flat2d" }
    )
    illustration.image.attach(io: StringIO.new(MINI_PNG), filename: "source.png", content_type: "image/png")
    style = illustration.prompt_style

    captured = {}
    switcher = Class.new { def switch(*) = true }
    client = Class.new do
      define_method(:inpaint) do |**kwargs|
        kwargs.each { |k, v| captured[k] = v }
        "inpainted-png"
      end
    end

    mask_data = "data:image/png;base64,#{Base64.strict_encode64(MINI_PNG)}"

    with_stubs(switcher:, client:) do
      InpaintMemoIllustrationJob.perform_now(
        illustration.id,
        mask_data: mask_data,
        inpaint_prompt_delta: "natural hands",
        include_style_prefix: true,
        include_style_suffix: true,
        denoising_strength: 0.55
      )
    end

    illustration.reload
    attachment = illustration.inpainted_images.attachments.first
    expected_prompt = [style.prompt_prefix, "natural hands", style.prompt_suffix].join(", ")

    assert_equal expected_prompt, captured[:prompt]
    assert_equal "natural hands", attachment.metadata["inpaint_note_translated"]
    assert_equal expected_prompt, attachment.metadata["inpaint_prompt"]
    assert attachment.metadata["inpaint_include_prefix"]
    assert attachment.metadata["inpaint_include_suffix"]
  end

  test "runs when status is already inpainting from controller submit" do
    illustration = MemoIllustration.create!(
      body: "サッカーボール",
      status: "inpainting",
      image_started_at: Time.current,
      style_id: prompt_styles(:chojugiga).style_id,
      positive_prompt: "girl holding soccer ball",
      resolved_negative_prompt: "bad hands",
      steps: 20,
      cfg_scale: 7.0,
      resolved_params: { "switch_key" => "flat2d" }
    )
    illustration.image.attach(io: StringIO.new(MINI_PNG), filename: "source.png", content_type: "image/png")

    switcher = Class.new { def switch(*) = true }
    client = Class.new do
      define_method(:inpaint) { |_kwargs| "inpainted-png" }
    end
    mask_data = "data:image/png;base64,#{Base64.strict_encode64(MINI_PNG)}"

    with_stubs(switcher:, client:) do
      InpaintMemoIllustrationJob.perform_now(
        illustration.id,
        mask_data: mask_data,
        inpaint_prompt_delta: "natural hands"
      )
    end

    illustration.reload
    assert_equal "completed", illustration.status
    assert illustration.inpainted_images.attached?
  end

  test "translates japanese note when delta is blank" do
    illustration = MemoIllustration.create!(
      body: "サッカーボール",
      status: "completed",
      style_id: prompt_styles(:chojugiga).style_id,
      positive_prompt: "girl holding soccer ball",
      resolved_negative_prompt: "bad hands",
      steps: 20,
      cfg_scale: 7.0,
      resolved_params: { "switch_key" => "flat2d" }
    )
    illustration.image.attach(io: StringIO.new(MINI_PNG), filename: "source.png", content_type: "image/png")

    captured = {}
    switcher = Class.new { def switch(*) = true }
    client = Class.new do
      define_method(:inpaint) do |**kwargs|
        kwargs.each { |k, v| captured[k] = v }
        "inpainted-png"
      end
    end
    translator = Class.new do
      def translate(_note)
        "natural hands, detailed fingers"
      end
    end.new

    mask_data = "data:image/png;base64,#{Base64.strict_encode64(MINI_PNG)}"
    original = InpaintNoteTranslator.method(:new)
    InpaintNoteTranslator.define_singleton_method(:new) { translator }

    with_stubs(switcher:, client:) do
      InpaintMemoIllustrationJob.perform_now(
        illustration.id,
        mask_data: mask_data,
        inpaint_note: "手を自然に、指をはっきり"
      )
    end

    illustration.reload
    attachment = illustration.inpainted_images.attachments.first

    assert_equal "natural hands, detailed fingers", captured[:prompt]
    assert_equal "手を自然に、指をはっきり", attachment.metadata["inpaint_note"]
    assert_equal "natural hands, detailed fingers", attachment.metadata["inpaint_note_translated"]
  ensure
    if defined?(original) && original
      InpaintNoteTranslator.singleton_class.send(:define_method, :new, original)
    end
  end
end
