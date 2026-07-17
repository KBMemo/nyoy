# frozen_string_literal: true

class MemoKnowledgeWebhookJob < ApplicationJob
  queue_as :default

  def perform(event_id)
    event = MemoRagWebhookEvent.find_by!(event_id: event_id)
    return if event.terminal?

    event.mark_processing!
    process_event(event)
  rescue StandardError => e
    event&.mark_failed!(e.message)
    raise
  end

  private

  def process_event(event)
    ingester = MemoKnowledgeIngester.new

    if event.deleted_event?
      ingester.delete_memo!(event.memo_uid)
      event.mark_completed!
      return
    end

    process_upsert(event, ingester)
  end

  def process_upsert(event, ingester)
    memo = fetch_memo(event, ingester)
    return unless memo

    if truthy?(memo["draft"])
      ingester.delete_memo!(event.memo_uid)
      event.mark_skipped!("memo is draft")
      return
    end

    if ingester.stale_memo_update?(event.memo_uid, event.memo_updated_at)
      event.mark_skipped!("stale memo update")
      return
    end

    ingester.ingest!(memo)
    event.mark_completed!
  end

  def fetch_memo(event, ingester)
    TsurezureClient.new.get_memo(event.memo_uid)
  rescue TsurezureClient::Error => e
    raise unless [ 403, 404 ].include?(e.status)

    ingester.delete_memo!(event.memo_uid)
    event.mark_skipped!("memo is not visible via kbmemo API")
    nil
  end

  def truthy?(value)
    ActiveModel::Type::Boolean.new.cast(value)
  end
end
