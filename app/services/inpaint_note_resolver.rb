# frozen_string_literal: true

class InpaintNoteResolver
  Result = Data.define(:original, :english, :translated)

  def self.call(note, translated: nil, translator: InpaintNoteTranslator.new)
    new(note, translated: translated, translator: translator).resolve
  end

  def initialize(note, translated: nil, translator: InpaintNoteTranslator.new)
    @note = note
    @translated = translated
    @translator = translator
  end

  def resolve
    original = @note.to_s.strip
    return Result.new(original: nil, english: nil, translated: false) if original.blank?

    english = @translated.to_s.strip.presence
    used_translation = false

    if english.blank? && InpaintNoteTranslator.japanese?(original)
      english = @translator.translate(original)
      used_translation = true
    end

    english ||= original

    Result.new(original: original, english: english, translated: used_translation)
  end
end
