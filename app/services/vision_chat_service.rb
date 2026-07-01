# frozen_string_literal: true

require "base64"

class VisionChatService
  class Error < StandardError; end

  MAX_TOKENS = 1024

  def initialize(
    client: LlamaCppClient.new(
      base_url: Rails.application.config.x.nyoy.vision_llama_cpp_url,
      model: Rails.application.config.x.nyoy.vision_llama_model
    )
  )
    @client = client
  end

  def analyze(image:, mime_type:, prompt:)
    raise Error, "画像がありません" if image.blank?

    text = prompt.to_s.strip
    raise Error, "プロンプトを入力してください" if text.blank?

    image, mime_type = ImageResizer.resize_to_limit(image, mime_type: mime_type)

    response = @client.chat(
      messages: [
        {
          role: "user",
          content: [
            { type: "image_url", image_url: { url: data_url(image, mime_type) } },
            { type: "text", text: text }
          ]
        }
      ],
      temperature: 0.2,
      max_tokens: MAX_TOKENS,
      read_timeout: Rails.application.config.x.nyoy.llama_read_timeout
    )

    result = LlamaCppClient.message_text(response)
    raise Error, "応答が空でした" if result.blank?

    result
  end

  private

  def data_url(image, mime_type)
    mime = mime_type.presence || "image/png"
    "data:#{mime};base64,#{Base64.strict_encode64(image)}"
  end
end
