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
    parts.concat(llama_cache_summary(synthesis["llama_cache"]))
    parts.concat(usage_summary(synthesis["usage"]))
    parts << "truncated" if updates["truncated"] == true || updates["draft_truncated"] == true
    parts
  end

  def llama_cache_summary(cache)
    return [] unless cache.is_a?(Hash)

    parts = []
    if cache["cache_prompt"] == true
      parts << "cache_prompt"
    end
    if cache["slot_id"].present?
      slot = cache["slot_id"]
      slot = "#{slot}/#{cache["slot_count"]}" if cache["slot_count"].present?
      parts << "slot: #{slot}"
    end
    parts
  end

  def usage_summary(usage)
    return [] unless usage.is_a?(Hash)

    parts = []
    parts << "in: #{usage["input_tokens"]}" if usage["input_tokens"].present?
    parts << "out: #{usage["output_tokens"]}" if usage["output_tokens"].present?
    parts << "cached: #{usage["cached_tokens"]}" if usage["cached_tokens"].present?
    parts
  end
end
