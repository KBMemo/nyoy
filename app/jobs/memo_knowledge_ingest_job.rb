# frozen_string_literal: true

class MemoKnowledgeIngestJob < ApplicationJob
  queue_as :default

  def perform(updated_since: nil)
    return unless ingest_enabled?

    started_at = Time.current
    checkpoint = updated_since.presence || AppSetting.memo_knowledge_last_ingested_at
    manual_checkpoint = updated_since.present?
    full_reconcile = checkpoint.blank?
    client = TsurezureClient.new
    ingester = MemoKnowledgeIngester.new
    cursor = nil
    ingested_memos = 0
    ingested_chunks = 0
    deleted_memos = 0
    deleted_chunks = 0
    deletion_sync_skipped = false
    exported_uids = []
    limit = Rails.application.config.x.nyoy.memo_ingest_page_limit

    loop do
      response = client.export_memos(
        updated_since: checkpoint,
        cursor: cursor,
        limit: limit
      )
      memos = response.fetch("memos", [])
      memos.each do |memo|
        exported_uids << memo["uid"] if full_reconcile
        ingested_chunks += ingester.ingest!(memo)
        ingested_memos += 1
      end

      pagination = response.fetch("pagination", {})
      cursor = pagination["next_cursor"]
      break if cursor.blank? || pagination["has_more"] == false
    end

    if full_reconcile
      deleted_chunks += ingester.delete_except_memos!(exported_uids)
    elsif checkpoint.present?
      deletion_result = sync_deletions(client: client, ingester: ingester, deleted_since: checkpoint, limit: limit)
      deleted_memos = deletion_result.fetch(:memos)
      deleted_chunks = deletion_result.fetch(:chunks)
      deletion_sync_skipped = deletion_result.fetch(:skipped)
    end

    AppSetting.update_memo_knowledge_last_ingested_at!(started_at) unless manual_checkpoint || deletion_sync_skipped

    Rails.logger.info(
      "MemoKnowledgeIngestJob: memos=#{ingested_memos} chunks=#{ingested_chunks} deleted_memos=#{deleted_memos} deleted_chunks=#{deleted_chunks} updated_since=#{checkpoint || 'all'}"
    )
  end

  private

  def sync_deletions(client:, ingester:, deleted_since:, limit:)
    cursor = nil
    deleted_memos = 0
    deleted_chunks = 0

    loop do
      response = client.export_memo_deletions(
        deleted_since: deleted_since,
        cursor: cursor,
        limit: limit
      )
      deletions = response.fetch("deletions", [])
      deletions.each do |deletion|
        uid = deletion["uid"].presence || deletion["memo_uid"]
        deleted_chunks += ingester.delete_memo!(uid)
        deleted_memos += 1
      end

      pagination = response.fetch("pagination", {})
      cursor = pagination["next_cursor"]
      break if cursor.blank? || pagination["has_more"] == false
    end

    { memos: deleted_memos, chunks: deleted_chunks, skipped: false }
  rescue TsurezureClient::Error => e
    raise unless e.status == 501 || e.code == "not_implemented"

    Rails.logger.info("MemoKnowledgeIngestJob: memo deletion feed is not implemented; skipping deletion sync")
    { memos: 0, chunks: 0, skipped: true }
  end

  def ingest_enabled?
    NyoyConnectionStore.enabled?(:kbmemo) && NyoyConnectionStore.api_token(:kbmemo).present?
  end
end
