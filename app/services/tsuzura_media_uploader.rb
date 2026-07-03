# frozen_string_literal: true

module TsuzuraMediaUploader
  CHAT_ALBUM_TITLE = "Nyoy Chat"

  module_function

  def archive_attachments!(attachments)
    return unless available?

    Array(attachments).each do |attachment|
      archive_attachment!(attachment)
    end
  end

  def archive_attachment!(attachment)
    return unless available?
    return if attachment.metadata["tsuzura_media_id"].present?

    upload = {
      io: StringIO.new(attachment.download),
      filename: attachment.filename.to_s,
      content_type: attachment.content_type
    }
    response = client.upload_batch(files: [upload], album_title: CHAT_ALBUM_TITLE)
    item = response.fetch("items", []).first
    return unless item

    attachment.update!(metadata: attachment.metadata.merge("tsuzura_media_id" => item["id"]))
  rescue TsuzuraClient::Error => e
    Rails.logger.warn("TsuzuraMediaUploader: #{e.message}")
  end

  def available?
    NyoyConnectionStore.enabled?(:tsuzura) && NyoyConnectionStore.api_token(:tsuzura).present?
  end

  def client
    TsuzuraClient.new
  end
end
