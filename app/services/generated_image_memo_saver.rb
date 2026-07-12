# frozen_string_literal: true

class GeneratedImageMemoSaver
  class Error < StandardError; end

  ALBUM_TITLE = "Nyoy 生成"

  def self.available?
    NyoyConnectionStore.enabled?(:kbmemo) && NyoyConnectionStore.api_token(:kbmemo).present? &&
      NyoyConnectionStore.enabled?(:tsuzura) && NyoyConnectionStore.api_token(:tsuzura).present?
  end

  def self.call(attachment:, source: nil, title: nil, tags: nil, tsurezure_client: nil, tsuzura_client: nil)
    new(
      attachment: attachment,
      source: source,
      title: title,
      tags: tags,
      tsurezure_client: tsurezure_client,
      tsuzura_client: tsuzura_client
    ).call
  end

  def initialize(attachment:, source: nil, title: nil, tags: nil, tsurezure_client: nil, tsuzura_client: nil)
    @attachment = attachment
    @source = source || attachment.record
    @title = title
    @tags = tags
    @tsurezure_client = tsurezure_client
    @tsuzura_client = tsuzura_client
  end

  def call
    raise Error, "徒然 API が未設定です（kbmemo の URL と API トークンを設定してください）" unless tsurezure_client.configured?
    raise Error, "葛籠 API が未設定です（tsuzura の URL と API トークンを設定してください）" unless tsuzura_client.configured?

    media_id = upload_image!
    body = GenerationMemoBodyBuilder.build(source: @source, attachment: @attachment)
    memo = tsurezure_client.create_memo(
      title: @title || GenerationMemoBodyBuilder.title_for(source: @source, attachment: @attachment),
      body: body,
      tags: @tags || GenerationMemoBodyBuilder.tags_for(@source)
    )
    append_media!(memo, media_id)
  end

  private

  def upload_image!
    existing = @attachment.metadata["tsuzura_media_id"]
    return existing if existing.present?

    response = tsuzura_client.upload_batch(
      files: [
        {
          io: StringIO.new(@attachment.download),
          filename: @attachment.filename.to_s,
          content_type: @attachment.content_type
        }
      ],
      album_title: ALBUM_TITLE
    )
    item = response.fetch("items", []).first
    media_id = item&.fetch("id", nil)
    raise Error, "葛籠へのアップロードに失敗しました" if media_id.blank?

    @attachment.update!(metadata: @attachment.metadata.merge("tsuzura_media_id" => media_id))
    media_id
  end

  def append_media!(memo, media_id)
    memo_ref = memo["uid"].presence || memo["id"]
    updated_at = memo["updated_at"]
    raise Error, "徒然メモの参照情報が不足しています" if memo_ref.blank? || updated_at.blank?

    fragment = ChatMemoMediaInserter.asciidoc_fragment([media_id])
    updated = tsurezure_client.update_memo(
      memo_ref,
      updated_at: updated_at,
      append_body: fragment,
      body_format: "asciidoc"
    )
    merged = updated.merge("appended_media_ids" => [media_id])
    merged["url"] = TsurezureMemoUrl.absolute(merged)
    merged
  rescue TsurezureClient::Error => e
    fallback = memo.merge("media_append_error" => e.message, "appended_media_ids" => [media_id])
    fallback["url"] = TsurezureMemoUrl.absolute(fallback)
    fallback
  end

  def tsurezure_client
    @tsurezure_client ||= TsurezureClient.new
  end

  def tsuzura_client
    @tsuzura_client ||= TsuzuraClient.new
  end
end
