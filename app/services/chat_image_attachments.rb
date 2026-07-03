# frozen_string_literal: true

module ChatImageAttachments
  PLACEHOLDER = "(画像を添付しました)"

  ALLOWED_CONTENT_TYPES = %w[image/jpeg image/png image/webp image/gif].freeze

  module_function

  def placeholder?(text)
    text.to_s.strip == PLACEHOLDER
  end

  def recent_attachments(chat, message_limit: 10)
    chat.messages.where(role: :user).order(id: :desc).limit(message_limit).flat_map do |message|
      next [] unless message.attachments.attached?

      message.attachments.order(:id).to_a
    end
  end

  def validate_uploads!(uploads)
    uploads.each do |upload|
      content_type = upload.content_type.to_s
      next if ALLOWED_CONTENT_TYPES.include?(content_type)

      raise ArgumentError, "画像ファイル（JPEG / PNG / WebP / GIF）のみ添付できます"
    end
  end
end
