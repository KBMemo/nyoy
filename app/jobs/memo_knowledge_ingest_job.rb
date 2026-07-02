# frozen_string_literal: true

class MemoKnowledgeIngestJob < ApplicationJob
  queue_as :default

  def perform(updated_since: nil)
    return unless ingest_enabled?

    client = TsurezureClient.new
    ingester = MemoKnowledgeIngester.new
    cursor = nil
    ingested_memos = 0
    ingested_chunks = 0
    limit = Rails.application.config.x.nyoy.memo_ingest_page_limit

    loop do
      response = client.export_memos(
        updated_since: updated_since,
        cursor: cursor,
        limit: limit
      )
      memos = response.fetch("memos", [])
      memos.each do |memo|
        ingested_chunks += ingester.ingest!(memo)
        ingested_memos += 1
      end

      pagination = response.fetch("pagination", {})
      cursor = pagination["next_cursor"]
      break if cursor.blank? || pagination["has_more"] == false
    end

    Rails.logger.info(
      "MemoKnowledgeIngestJob: memos=#{ingested_memos} chunks=#{ingested_chunks} updated_since=#{updated_since || 'all'}"
    )
  end

  private

  def ingest_enabled?
    NyoyConnectionStore.enabled?(:kbmemo) && NyoyConnectionStore.api_token(:kbmemo).present?
  end
end
