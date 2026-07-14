# frozen_string_literal: true

class AgentCheckpoint < ApplicationRecord
  belongs_to :agent_run

  validates :node_name, presence: true
end
