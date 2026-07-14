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

  def merge_state!(updates)
    self.state = (state || {}).deep_merge(updates.stringify_keys)
    save!
  end
end
