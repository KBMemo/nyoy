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
      parts.concat(planning_summary(updates["planning"]))
      parts.concat(evaluation_summary(updates["evidence_review"]))
      parts.concat(vision_summary(updates["analysis_meta"]))
      parts.concat(synthesis_summary(updates))
    end
    parts << "goto: #{output_snapshot["goto"]}" if output_snapshot["goto"].present?
    parts << "interrupt" if output_snapshot["interrupt"] == true
    parts << "error: #{output_snapshot["error"]}" if output_snapshot["error"].present?
    parts.presence || [ "no output" ]
  end

  private

  def planning_summary(planning)
    return [] unless planning.is_a?(Hash)

    metadata_summary(planning) +
      llama_cache_summary(planning["llama_cache"]) +
      usage_summary(planning["usage"])
  end

  def synthesis_summary(updates)
    synthesis = updates["final_synthesis"] || updates["draft_synthesis"]
    return [] unless synthesis.is_a?(Hash)

    parts = metadata_summary(synthesis)
    parts.concat(evidence_summary(synthesis["evidence"]))
    parts.concat(llama_cache_summary(synthesis["llama_cache"]))
    parts.concat(usage_summary(synthesis["usage"]))
    parts << "truncated" if updates["truncated"] == true || updates["draft_truncated"] == true
    parts
  end

  def evaluation_summary(review)
    return [] unless review.is_a?(Hash)

    metadata_summary(review) +
      llama_cache_summary(review["llama_cache"]) +
      usage_summary(review["usage"])
  end

  def vision_summary(metadata)
    return [] unless metadata.is_a?(Hash)

    metadata_summary(metadata) + usage_summary(metadata["usage"])
  end

  def metadata_summary(metadata)
    parts = []
    if metadata["profile"].present?
      role = metadata["role"].presence
      profile = [ role, metadata["profile"] ].compact.join(".")
      parts << "profile: #{profile}"
    end
    parts << "llm: #{metadata["model_id"]}" if metadata["model_id"].present?
    parts << "source: #{metadata["source"]}" if metadata["source"].present?
    parts << "fallback: #{metadata["fallback"]}" if metadata["fallback"].present?
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

  def evidence_summary(evidence)
    return [] unless evidence.is_a?(Hash)

    parts = []
    parts << "memo: #{evidence["memo"]}" if evidence.key?("memo")
    parts << "search: #{evidence["search_results"]}" if evidence.key?("search_results")
    parts << "fetched: #{evidence["fetched_pages"]}" if evidence.key?("fetched_pages")
    parts << "errors: #{evidence["errors"]}" if evidence.key?("errors")
    parts
  end
end
