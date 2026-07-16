# frozen_string_literal: true

module AgentGraph
  module ImageUnderstandingIntent
    IMAGE_REFERENCE_PATTERN = Regexp.union(
      /この画像/,
      /画像/,
      /写真/,
      /スクショ/,
      /スクリーンショット/,
      /写って/,
      /何が/,
      /読んで/,
      /説明して/,
      /見える/,
      /visual/i,
      /image/i,
      /photo/i,
      /screenshot/i
    )

    GENERATION_PATTERN = Regexp.union(
      /画像(を)?生成/,
      /画像(を)?作/,
      /イラスト(を)?作/,
      /描いて/,
      /generate[_ ]?image/i
    )

    module_function

    def decision(message)
      return no_match("no_user_message") unless message
      return no_match("no_attachment") unless message.attachments.attached?

      text = message.content.to_s.strip
      return no_match("image_generation") if text.match?(GENERATION_PATTERN)

      if text.blank? || ChatImageAttachments.placeholder?(text)
        return match("attachment_only", [ "attachment" ])
      end

      if text.match?(IMAGE_REFERENCE_PATTERN)
        return match("image_reference", [ "attachment", "image_reference" ])
      end

      no_match("no_image_reference")
    end

    def match(reason, hits)
      { match: true, reason: reason, hits: hits }
    end

    def no_match(reason)
      { match: false, reason: reason, hits: [] }
    end
  end
end
