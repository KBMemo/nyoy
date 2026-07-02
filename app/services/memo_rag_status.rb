# frozen_string_literal: true

class MemoRagStatus
  Stats = Data.define(:chunk_count, :memo_count, :last_synced_at, :enabled)

  def self.current
    new.report
  end

  def report
    enabled = ChatMemoRagInjector.enabled?
    scope = PromptKnowledgeChunk.from_memo
    chunk_count = scope.count
    memo_count = scope.where("metadata ? 'memo_uid'")
                      .distinct
                      .count("metadata->>'memo_uid'")
    last_synced_at = scope.maximum("(metadata->>'memo_updated_at')::timestamptz")

    Stats.new(
      chunk_count: chunk_count,
      memo_count: memo_count,
      last_synced_at: last_synced_at,
      enabled: enabled
    )
  rescue ActiveRecord::StatementInvalid
    Stats.new(chunk_count: 0, memo_count: 0, last_synced_at: nil, enabled: enabled)
  end
end
