# frozen_string_literal: true

class AgentRun < ApplicationRecord
  STATUSES = %w[
    pending
    running
    awaiting_approval
    completed
    failed
    cancelled
  ].freeze

  belongs_to :chat
  has_many :agent_checkpoints, dependent: :destroy
  has_many :agent_node_runs, dependent: :destroy

  validates :graph_name, :status, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(created_at: :desc) }
  scope :awaiting_approval, -> { where(status: "awaiting_approval") }
  # Still status=awaiting_approval but decision not yet submitted (or blank).
  scope :pending_decision, -> {
    awaiting_approval.where(
      "(state->>'approval') IS NULL OR (state->>'approval') IN (?, ?)",
      "", "pending"
    )
  }

  def running?
    status == "running"
  end

  def completed?
    status == "completed"
  end

  def failed?
    status == "failed"
  end

  def awaiting_approval?
    status == "awaiting_approval"
  end

  def state_summary
    keys = state.is_a?(Hash) ? state.keys : []
    return "empty state" if keys.empty?

    "state: #{keys.join(", ")}"
  end

  def failed_node_run
    agent_node_runs.where(status: "failed").order(:id).last
  end

  def latest_checkpoint
    agent_checkpoints.order(:id).last
  end

  def recovery_candidates
    return [] unless failed?

    candidates = []
    if failed_node_run
      candidates << "失敗 node: #{failed_node_run.node_name}"
    elsif current_node.present?
      candidates << "失敗推定 node: #{current_node}"
    end

    if latest_checkpoint
      candidates << "最後の checkpoint: #{latest_checkpoint.node_name} ##{latest_checkpoint.id}"
    else
      candidates << "checkpoint なし"
    end

    candidates << "次の実装候補: 最後の checkpoint から複製 run を作成して再実行"
    candidates
  end

  def recovery_summary
    return unless failed?

    node = failed_node_run&.node_name || current_node.presence || "不明"
    checkpoint = latest_checkpoint
    checkpoint_label = checkpoint ? "#{checkpoint.node_name} ##{checkpoint.id}" : "checkpoint なし"
    "失敗 node: #{node} / 最後の checkpoint: #{checkpoint_label}"
  end

  def merge_state!(updates)
    self.state = (state || {}).deep_merge(updates.stringify_keys)
    save!
  end
end
