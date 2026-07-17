# frozen_string_literal: true

class MemoRagWebhookEvent < ApplicationRecord
  EVENT_TYPES = %w[memo.created memo.updated memo.deleted].freeze
  STATUSES = %w[pending processing completed failed skipped].freeze
  TERMINAL_STATUSES = %w[completed skipped].freeze

  validates :event_id, :event_type, :account_id, :memo_uid, :occurred_at, :status, presence: true
  validates :event_id, uniqueness: true
  validates :event_type, inclusion: { in: EVENT_TYPES }
  validates :status, inclusion: { in: STATUSES }

  def terminal?
    TERMINAL_STATUSES.include?(status)
  end

  def deleted_event?
    event_type == "memo.deleted"
  end

  def upsert_event?
    event_type == "memo.created" || event_type == "memo.updated"
  end

  def mark_processing!
    update!(status: "processing", error_message: nil)
  end

  def mark_completed!
    update!(status: "completed", error_message: nil, processed_at: Time.current)
  end

  def mark_skipped!(message)
    update!(status: "skipped", error_message: message, processed_at: Time.current)
  end

  def mark_failed!(message)
    update!(status: "failed", error_message: message)
  end
end
