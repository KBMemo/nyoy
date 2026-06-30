# frozen_string_literal: true

require "ostruct"

class InpaintNoteTranslator
  SYSTEM_PROMPT = <<~PROMPT.squish
    You translate Japanese inpainting correction notes into short English Stable Diffusion prompt fragments.
    The user is fixing only a masked region of an existing image via img2img inpaint.
    Output comma-separated English tags and short phrases describing the corrected detail only.
    Focus on anatomy, hands, fingers, objects, textures, and local fixes.
    Do not rewrite the whole scene. Do not add quality tags unless the note asks for them.
    Output only the English fragment with no explanation, quotes, or markdown.
  PROMPT

  SKILL_TITLE = "部分修正翻訳"

  class Error < StandardError; end

  def self.japanese?(text)
    text.to_s.match?(/\p{Han}|\p{Hiragana}|\p{Katakana}/)
  end

  def initialize(translator: SdPromptTranslator.new)
    @translator = translator
  end

  def translate(japanese_note)
    note = japanese_note.to_s.strip
    raise Error, "修正指示が空です" if note.blank?

    @translator.translate(note, skill: translation_skill)
  rescue SdPromptTranslator::Error => e
    raise Error, e.message
  end

  private

  def translation_skill
    chunk = PromptKnowledgeChunk.find_by(kind: "inpaint", title: SKILL_TITLE)
    return OpenStruct.new(body: SYSTEM_PROMPT) unless chunk&.body.present?

    chunk
  end
end
