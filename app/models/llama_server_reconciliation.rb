# frozen_string_literal: true

class LlamaServerReconciliation < ApplicationRecord
  STATUSES = %w[healthy warning failed].freeze

  belongs_to :service_connection

  validates :status, inclusion: { in: STATUSES }
  validates :checked_at, presence: true
  validate :service_connection_must_be_switchd

  scope :recent, -> { order(checked_at: :desc) }

  def healthy?
    status == "healthy"
  end

  private

  def service_connection_must_be_switchd
    return if service_connection&.key == "llama_switchd"

    errors.add(:service_connection, "は llama_switchd 接続を指定してください")
  end
end
