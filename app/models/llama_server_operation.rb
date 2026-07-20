# frozen_string_literal: true

class LlamaServerOperation < ApplicationRecord
  DEFINITION_ACTIONS = %w[create update delete].freeze
  LIFECYCLE_ACTIONS = %w[start stop restart enable disable].freeze
  ACTIONS = (DEFINITION_ACTIONS + LIFECYCLE_ACTIONS).freeze
  STATUSES = %w[queued running succeeded failed].freeze
  ACTIVE_STATUSES = %w[queued running].freeze
  ACTION_LABELS = {
    "start" => "起動", "stop" => "停止", "restart" => "再起動",
    "enable" => "自動起動を有効化", "disable" => "自動起動を無効化",
    "create" => "定義作成", "update" => "定義更新", "delete" => "定義削除"
  }.freeze
  STATUS_LABELS = {
    "queued" => "待機中", "running" => "実行中", "succeeded" => "成功", "failed" => "失敗"
  }.freeze

  belongs_to :service_connection

  validates :managed_server_id, presence: true
  validates :managed_server_id, format: { with: /\A[a-zA-Z0-9][a-zA-Z0-9._-]*\z/ }
  validates :action, inclusion: { in: ACTIONS }
  validates :status, inclusion: { in: STATUSES }
  validate :service_connection_must_be_switchd

  scope :recent, -> { order(created_at: :desc) }
  scope :active, -> { where(status: ACTIVE_STATUSES) }

  def active?
    status.in?(ACTIVE_STATUSES)
  end

  def action_label
    ACTION_LABELS.fetch(action, action)
  end

  def status_label
    STATUS_LABELS.fetch(status, status)
  end

  private

  def service_connection_must_be_switchd
    return if service_connection&.key == "llama_switchd"

    errors.add(:service_connection, "は llama_switchd 接続を指定してください")
  end
end
