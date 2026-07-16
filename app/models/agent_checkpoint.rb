# frozen_string_literal: true

class AgentCheckpoint < ApplicationRecord
  belongs_to :agent_run

  validates :node_name, presence: true

  def state_summary
    keys = state.is_a?(Hash) ? state.keys : []
    return "empty state" if keys.empty?

    "state: #{keys.join(", ")}"
  end
end
