# frozen_string_literal: true

module ChatMemoMediaInserter
  module_function

  def append_media_to_memo!(client, chat, memo)
    return memo unless chat

    media_ids = media_ids_from_chat(chat)
    return memo if media_ids.empty?

    memo_ref = memo["uid"].presence || memo["id"]
    updated_at = memo["updated_at"]
    return memo if memo_ref.blank? || updated_at.blank?

    fragment = asciidoc_fragment(media_ids)
    updated = client.update_memo(
      memo_ref,
      updated_at: updated_at,
      append_body: fragment,
      body_format: "asciidoc"
    )
    updated.merge("appended_media_ids" => media_ids)
  rescue TsurezureClient::Error => e
    memo.merge("media_append_error" => e.message, "appended_media_ids" => media_ids)
  end

  def media_ids_from_chat(chat)
    attachments = ChatImageAttachments.recent_attachments(chat)
    TsuzuraMediaUploader.archive_attachments!(attachments) if TsuzuraMediaUploader.available?

    attachments.filter_map { |attachment| attachment.metadata["tsuzura_media_id"].presence }.uniq
  end

  def asciidoc_fragment(media_ids)
    Array(media_ids).map { |media_id| "image::media:#{media_id}[]" }.join("\n")
  end
end
