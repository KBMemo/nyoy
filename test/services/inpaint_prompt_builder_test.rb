# frozen_string_literal: true

require "test_helper"

class InpaintPromptBuilderTest < ActiveSupport::TestCase
  test "builds delta-only prompt by default" do
    illustration = MemoIllustration.new(body: "メモ", style_id: prompt_styles(:chojugiga).style_id)

    result = InpaintPromptBuilder.call(
      illustration: illustration,
      inpaint_prompt_delta: "natural hands",
      include_prefix: false,
      include_suffix: false
    )

    assert_equal "natural hands", result.prompt
    assert_equal "natural hands", result.delta
    assert_not result.include_prefix
    assert_not result.include_suffix
  end

  test "includes prefix and suffix when requested" do
    illustration = MemoIllustration.new(body: "メモ", style_id: prompt_styles(:chojugiga).style_id)
    style = illustration.prompt_style

    result = InpaintPromptBuilder.call(
      illustration: illustration,
      inpaint_prompt_delta: "natural hands",
      include_prefix: true,
      include_suffix: true
    )

    assert_equal [style.prompt_prefix, "natural hands", style.prompt_suffix].join(", "), result.prompt
    assert result.include_prefix
    assert result.include_suffix
  end

  test "translates japanese note when delta is blank" do
    illustration = MemoIllustration.new(body: "メモ", style_id: prompt_styles(:chojugiga).style_id)
    translator = Class.new do
      def translate(_note)
        "natural hands"
      end
    end.new

    result = InpaintPromptBuilder.call(
      illustration: illustration,
      inpaint_note: "手を自然に",
      include_prefix: false,
      include_suffix: false,
      translator: translator
    )

    assert_equal "natural hands", result.prompt
    assert_equal "手を自然に", result.note_result.original
    assert result.note_result.translated
  end

  test "raises when no delta or note" do
    illustration = MemoIllustration.new(body: "メモ", style_id: prompt_styles(:chojugiga).style_id)

    assert_raises(RuntimeError) do
      InpaintPromptBuilder.call(illustration: illustration)
    end
  end
end
