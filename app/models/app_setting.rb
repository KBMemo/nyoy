# frozen_string_literal: true

# Singleton preferences for app-wide behavior that is not owned by an LLM usage assignment.
class AppSetting < ApplicationRecord
  RESEARCH_DRAFT_FALLBACKS = %w[main template].freeze

  before_validation :normalize_research_draft_fallback
  validate :research_draft_fallback_must_be_allowed
  validate :agent_graph_role_profiles_must_be_available

  class << self
    def instance
      first || create!
    end

    # "main" = retry with chat model then template; "template" = evidence pack only.
    def research_draft_fallback
      value = instance.research_draft_fallback.to_s.presence
      RESEARCH_DRAFT_FALLBACKS.include?(value) ? value : "main"
    end

    def memo_knowledge_last_ingested_at
      instance.memo_knowledge_last_ingested_at
    end

    def update_memo_knowledge_last_ingested_at!(time)
      instance.update!(memo_knowledge_last_ingested_at: time)
    end
  end

  def agent_graph_draft_profile
    agent_graph_role_profiles.to_h["draft"].to_s.presence
  end

  def agent_graph_draft_profile=(profile)
    profiles = agent_graph_role_profiles.to_h.stringify_keys
    value = profile.to_s.presence

    if value
      profiles["draft"] = value
    else
      profiles.delete("draft")
    end

    self.agent_graph_role_profiles = profiles
  end

  def agent_graph_planner_profile
    agent_graph_role_profiles.to_h["planner"].to_s.presence
  end

  def agent_graph_planner_profile=(profile)
    profiles = agent_graph_role_profiles.to_h.stringify_keys
    value = profile.to_s.presence
    value ? profiles["planner"] = value : profiles.delete("planner")
    self.agent_graph_role_profiles = profiles
  end

  def agent_graph_intent_profile
    agent_graph_role_profiles.to_h["intent"].to_s.presence
  end

  def agent_graph_final_answer_profile
    agent_graph_role_profiles.to_h["final_answer"].to_s.presence
  end

  def agent_graph_final_answer_profile=(profile)
    profiles = agent_graph_role_profiles.to_h.stringify_keys
    value = profile.to_s.presence
    value ? profiles["final_answer"] = value : profiles.delete("final_answer")
    self.agent_graph_role_profiles = profiles
  end

  def agent_graph_evidence_evaluator_profile
    agent_graph_role_profiles.to_h["evidence_evaluator"].to_s.presence
  end

  def agent_graph_evidence_evaluator_profile=(profile)
    profiles = agent_graph_role_profiles.to_h.stringify_keys
    value = profile.to_s.presence
    value ? profiles["evidence_evaluator"] = value : profiles.delete("evidence_evaluator")
    self.agent_graph_role_profiles = profiles
  end

  def agent_graph_intent_profile=(profile)
    profiles = agent_graph_role_profiles.to_h.stringify_keys
    value = profile.to_s.presence
    value ? profiles["intent"] = value : profiles.delete("intent")
    self.agent_graph_role_profiles = profiles
  end

  private

  def normalize_research_draft_fallback
    self.research_draft_fallback = research_draft_fallback.to_s.presence || "main"
  end

  def research_draft_fallback_must_be_allowed
    value = research_draft_fallback.to_s.presence || "main"
    return if RESEARCH_DRAFT_FALLBACKS.include?(value)

    errors.add(:research_draft_fallback, "は main か template を選んでください")
  end

  def agent_graph_role_profiles_must_be_available
    agent_graph_role_profiles.to_h.each do |role, profile|
      available = AgentGraph::RoleServices.profile_names(role)
      next if available.include?(profile.to_s.to_sym)

      errors.add(:agent_graph_role_profiles, "#{role}.#{profile} は登録されていません")
    rescue KeyError
      errors.add(:agent_graph_role_profiles, "#{role} は登録されていない role です")
    end
  end
end
