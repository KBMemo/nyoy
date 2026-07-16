# frozen_string_literal: true

class AgentNodeRun < ApplicationRecord
  STATUSES = %w[pending running completed failed skipped].freeze

  belongs_to :agent_run

  validates :node_name, :status, presence: true
  validates :status, inclusion: { in: STATUSES }

  def elapsed_seconds
    return unless started_at

    ((finished_at || Time.current) - started_at).clamp(0, Float::INFINITY)
  end

  def output_summary
    parts = []
    updates = output_snapshot["updates"]
    if updates.is_a?(Hash) && updates.any?
      parts << "updates: #{updates.keys.join(", ")}"
      parts.concat(synthesis_summary(updates))
    end
    parts << "goto: #{output_snapshot["goto"]}" if output_snapshot["goto"].present?
    parts << "interrupt" if output_snapshot["interrupt"] == true
    parts << "error: #{output_snapshot["error"]}" if output_snapshot["error"].present?
    parts.presence || [ "no output" ]
  end

  private

  def synthesis_summary(updates)
    synthesis = updates["final_synthesis"] || updates["draft_synthesis"]
    return [] unless synthesis.is_a?(Hash)

    parts = []
    parts << "llm: #{synthesis["model_id"]}" if synthesis["model_id"].present?
    parts << "source: #{synthesis["source"]}" if synthesis["source"].present?
    parts << "truncated" if updates["truncated"] == true || updates["draft_truncated"] == true
    parts
  end
end
