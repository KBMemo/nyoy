# frozen_string_literal: true

class InpaintPromptBuilder
  Result = Data.define(:prompt, :delta, :note_result, :include_prefix, :include_suffix)

  def self.call(illustration:, inpaint_note: nil, inpaint_prompt_delta: nil, include_prefix: false, include_suffix: false, translator: InpaintNoteTranslator.new)
    new(
      illustration: illustration,
      inpaint_note: inpaint_note,
      inpaint_prompt_delta: inpaint_prompt_delta,
      include_prefix: include_prefix,
      include_suffix: include_suffix,
      translator: translator
    ).call
  end

  def initialize(illustration:, inpaint_note:, inpaint_prompt_delta:, include_prefix:, include_suffix:, translator:)
    @illustration = illustration
    @inpaint_note = inpaint_note
    @inpaint_prompt_delta = inpaint_prompt_delta
    @include_prefix = include_prefix
    @include_suffix = include_suffix
    @translator = translator
  end

  def call
    note_result = nil
    delta = @inpaint_prompt_delta.to_s.strip

    if delta.blank? && @inpaint_note.to_s.strip.present?
      note_result = InpaintNoteResolver.call(@inpaint_note, translator: @translator)
      delta = note_result.english
    end

    raise "修正指示または英語プロンプトを入力してください" if delta.blank?

    prompt = @illustration.build_inpaint_prompt(
      delta: delta,
      include_prefix: @include_prefix,
      include_suffix: @include_suffix
    )

    Result.new(
      prompt: prompt,
      delta: delta,
      note_result: note_result,
      include_prefix: @include_prefix,
      include_suffix: @include_suffix
    )
  end
end
