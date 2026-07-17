# frozen_string_literal: true

class MemoRagWebhookStatus
  Event = Data.define(:event_id, :event_type, :status, :memo_uid, :error_message, :occurred_at, :processed_at)
  Stats = Data.define(
    :enabled,
    :secret_configured,
    :total_events,
    :status_counts,
    :recent_events,
    :failed_events,
    :stuck_events,
    :last_received_at,
    :last_processed_at
  )

  DEFAULT_LIMIT = 10
  STUCK_AFTER = 10.minutes

  def self.current(limit: DEFAULT_LIMIT)
    new(limit: limit).report
  end

  def initialize(limit: DEFAULT_LIMIT)
    @limit = limit.to_i.clamp(1, 50)
  end

  def report
    scope = MemoRagWebhookEvent.all

    Stats.new(
      enabled: webhook_enabled?,
      secret_configured: webhook_secret_configured?,
      total_events: scope.count,
      status_counts: status_counts(scope),
      recent_events: snapshot(scope.order(created_at: :desc).limit(@limit)),
      failed_events: snapshot(scope.where(status: "failed").order(updated_at: :desc).limit(@limit)),
      stuck_events: snapshot(stuck_scope(scope).order(updated_at: :asc).limit(@limit)),
      last_received_at: scope.maximum(:created_at),
      last_processed_at: scope.where.not(processed_at: nil).maximum(:processed_at)
    )
  end

  private

  def webhook_enabled?
    Rails.application.config.x.nyoy.memo_rag_webhook_enabled
  end

  def webhook_secret_configured?
    Rails.application.config.x.nyoy.memo_rag_webhook_secret.present?
  end

  def status_counts(scope)
    counts = scope.group(:status).count
    MemoRagWebhookEvent::STATUSES.index_with { |status| counts.fetch(status, 0) }
  end

  def stuck_scope(scope)
    scope.where(status: %w[pending processing]).where(updated_at: ...STUCK_AFTER.ago)
  end

  def snapshot(scope)
    scope.map do |event|
      Event.new(
        event_id: event.event_id,
        event_type: event.event_type,
        status: event.status,
        memo_uid: event.memo_uid,
        error_message: event.error_message,
        occurred_at: event.occurred_at,
        processed_at: event.processed_at
      )
    end
  end
end
