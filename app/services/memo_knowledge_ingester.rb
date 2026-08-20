# frozen_string_literal: true

class MemoKnowledgeIngester
  class Error < StandardError; end

  def initialize(
    chunker: MemoTextChunker.new,
    client: EmbeddingClient.new,
    dimensions: Rails.application.config.x.nyoy.embedding_dimensions
  )
    @chunker = chunker
    @client = client
    @dimensions = dimensions
  end

  def ingest!(memo)
    uid = memo["uid"].to_s.strip
    raise Error, "memo uid required" if uid.blank?

    body = ChatTools::ToolResponse.safe_string(memo["body"])
    title = memo["title"].to_s.presence || "（無題）"
    updated_at = memo["updated_at"].to_s
    memo_id = memo["id"]

    sections = @chunker.chunk(body)
    PromptKnowledgeChunk.from_memo.where("metadata->>'memo_uid' = ?", uid).delete_all
    return 0 if sections.empty?

    records = sections.each_with_index.map do |content, index|
      build_record(
        memo_uid: uid,
        memo_id: memo_id,
        title: title,
        content: content,
        index: index,
        chunk_count: sections.size,
        memo_updated_at: updated_at
      )
    end

    vectors = batch_embed(records.map(&:embed_text))

    records.each_with_index do |record, index|
      record.skip_auto_embed = true
      record.embedding = vectors[index]
      record.save!
    end

    records.size
  end

  def delete_memo!(memo_uid)
    uid = memo_uid.to_s.strip
    raise Error, "memo uid required" if uid.blank?

    PromptKnowledgeChunk.from_memo.where("metadata->>'memo_uid' = ?", uid).delete_all
  end

  def delete_except_memos!(memo_uids)
    uids = Array(memo_uids).map { |uid| uid.to_s.strip }.reject(&:blank?).uniq
    scope = PromptKnowledgeChunk.from_memo
    return scope.delete_all if uids.empty?

    scope.where.not("metadata->>'memo_uid' IN (?)", uids).delete_all
  end

  def stale_memo_update?(memo_uid, memo_updated_at)
    uid = memo_uid.to_s.strip
    update_time = parse_time(memo_updated_at)
    return false if uid.blank? || update_time.blank?

    latest = latest_chunk_time(uid)
    latest.present? && latest >= update_time
  end

  private

  def latest_chunk_time(memo_uid)
    PromptKnowledgeChunk.from_memo
                        .where("metadata->>'memo_uid' = ?", memo_uid)
                        .pluck(Arel.sql("metadata->>'memo_updated_at'"))
                        .filter_map { |value| parse_time(value) }
                        .max
  end

  def parse_time(value)
    return value if value.is_a?(Time)
    return value.to_time if value.respond_to?(:to_time) && !value.is_a?(String)

    Time.iso8601(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def build_record(memo_uid:, memo_id:, title:, content:, index:, chunk_count:, memo_updated_at:)
    PromptKnowledgeChunk.new(
      source: PromptKnowledgeChunk::SOURCE_MEMO,
      kind: "memo",
      external_id: PromptKnowledgeChunk.memo_external_id(memo_uid, index),
      title: chunk_title(title, index, chunk_count),
      body: content,
      metadata: {
        memo_uid: memo_uid,
        memo_id: memo_id,
        chunk_index: index,
        chunk_count: chunk_count,
        memo_updated_at: memo_updated_at,
        token_count: estimate_tokens(content)
      }
    )
  end

  def chunk_title(title, index, chunk_count)
    return title if chunk_count <= 1

    "#{title} (#{index + 1}/#{chunk_count})"
  end

  def batch_embed(texts)
    texts.map do |text|
      vector = @client.embed(input: EmbeddingInput.truncate(text))
      validate_dimensions!(vector)
      vector
    end
  rescue EmbeddingClient::Error => e
    raise Error, e.message
  end

  def validate_dimensions!(vector)
    return if vector.length == @dimensions

    raise Error, "expected #{@dimensions} dimensions, got #{vector.length}"
  end

  def estimate_tokens(text)
    (text.to_s.length / 4.0).ceil
  end
end
