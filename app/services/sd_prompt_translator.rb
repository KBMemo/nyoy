# frozen_string_literal: true

class SdPromptTranslator
  SYSTEM_PROMPT = <<~PROMPT.squish
    You translate Japanese image descriptions into English Stable Diffusion prompts.
    Output comma-separated tags and phrases suitable for txt2img.
    Include quality tags when appropriate (masterpiece, best quality, etc.).
    Output only the English prompt with no explanation, quotes, or markdown.
  PROMPT

  class Error < StandardError; end

  def initialize(client: LlamaCppClient.new)
    @client = client
  end

  def translate(japanese_prompt)
    response = @client.chat(
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: japanese_prompt }
      ]
    )

    content = response.dig("choices", 0, "message", "content").to_s.strip
    raise Error, "empty translation" if content.blank?

    content
  end
end
