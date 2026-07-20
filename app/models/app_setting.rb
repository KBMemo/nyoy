# frozen_string_literal: true

# Singleton preferences for app-wide defaults (editable from the settings UI).
# Blank columns fall back to ENV / config.x.nyoy values.
class AppSetting < ApplicationRecord
  RESEARCH_DRAFT_FALLBACKS = %w[main template].freeze

  before_validation :normalize_research_draft_fallback

  validate :connection_keys_must_be_available
  validate :sampling_preset_key_must_be_available
  validate :research_draft_model_must_be_available
  validate :research_planner_model_must_be_available
  validate :research_draft_fallback_must_be_allowed
  validate :agent_graph_role_profiles_must_be_available

  class << self
    def instance
      first || create!
    end

    def default_chat_connection_key
      resolve(
        :default_chat_connection_key,
        env_fallback: Rails.application.config.x.nyoy.default_chat_connection_key
      )
    end

    def default_style_plan_connection_key
      resolve(
        :default_style_plan_connection_key,
        env_fallback: Rails.application.config.x.nyoy.style_plan_connection_key
      )
    end

    # Normalized chat sampling hash from the selected preset, or {} when unset/invalid.
    def default_chat_llm_params
      key = instance.default_llm_sampling_preset_key.to_s.presence
      return {} if key.blank?

      preset = LlmSamplingPreset.enabled.find_by(key: key)
      return {} unless preset

      ChatLlmSettings.normalize(preset.sampling_params.to_h)
    end

    # Preferred Model for Research Graph draft synthesis (nil = use chat model).
    def research_draft_model
      model_id = instance.research_draft_model_id.to_s.presence
      return nil if model_id.blank?

      Model.find_by(provider: "openai", model_id: model_id)
    end

    def research_planner_model
      model_id = instance.research_planner_model_id.to_s.presence
      return nil if model_id.blank?

      Model.find_by(provider: "openai", model_id: model_id)
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

    private

    def resolve(column, env_fallback:)
      keys = available_connection_keys
      stored = instance.public_send(column).to_s.presence
      return stored if stored && keys.include?(stored)

      preferred = env_fallback.to_s.presence
      return preferred if preferred && keys.include?(preferred)

      keys.first
    end

    def available_connection_keys
      StylePlanModelCatalog.connection_keys
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

  private

  def normalize_research_draft_fallback
    self.research_draft_fallback = research_draft_fallback.to_s.presence || "main"
  end

  def connection_keys_must_be_available
    keys = StylePlanModelCatalog.connection_keys
    validate_connection_key(:default_chat_connection_key, keys)
    validate_connection_key(:default_style_plan_connection_key, keys)
  end

  def sampling_preset_key_must_be_available
    key = default_llm_sampling_preset_key.to_s.presence
    return if key.blank?
    return if LlmSamplingPreset.enabled.exists?(key: key)

    errors.add(:default_llm_sampling_preset_key, "は有効なサンプリングプリセットを選んでください")
  end

  def research_draft_model_must_be_available
    model_id = research_draft_model_id.to_s.presence
    return if model_id.blank?

    available = ChatModelCatalog.model_ids
    return if available.include?(model_id)

    errors.add(:research_draft_model_id, "は有効なチャットモデルを選んでください")
  end

  def research_planner_model_must_be_available
    model_id = research_planner_model_id.to_s.presence
    return if model_id.blank? || ChatModelCatalog.model_ids.include?(model_id)

    errors.add(:research_planner_model_id, "は有効なチャットモデルを選んでください")
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

  def validate_connection_key(attribute, keys)
    value = public_send(attribute).to_s.presence
    return if value.blank?
    return if keys.include?(value)

    errors.add(attribute, "は有効な接続を選んでください")
  end
end
