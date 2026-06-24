# frozen_string_literal: true

class SdPromptTranslator
  SYSTEM_PROMPT = <<~PROMPT.squish
    You translate Japanese image descriptions into English Stable Diffusion prompts.
    Output comma-separated tags and phrases suitable for txt2img.
    Include quality tags when appropriate (masterpiece, best quality, etc.).
    Output only the English prompt with no explanation, quotes, or markdown.
  PROMPT

  MAX_TOKENS = 2048

  class Error < StandardError; end

  def initialize(client: LlamaCppClient.new)
    @client = client
  end

  def translate(japanese_prompt, skill: nil)
    system_prompt = skill&.body.presence || SYSTEM_PROMPT

    response = @client.chat(
      messages: [
        { role: "system", content: system_prompt },
        { role: "user", content: japanese_prompt }
      ],
      temperature: 0.2,
      max_tokens: MAX_TOKENS
    )

    content = LlamaCppClient.message_text(response)
    raise Error, "empty translation" if content.blank?

    content
  end
end
