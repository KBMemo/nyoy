# frozen_string_literal: true

class AgentNodeRun < ApplicationRecord
  STATUSES = %w[pending running completed failed skipped].freeze

  belongs_to :agent_run

  validates :node_name, :status, presence: true
  validates :status, inclusion: { in: STATUSES }
end
