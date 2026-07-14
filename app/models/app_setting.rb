# frozen_string_literal: true

# Singleton preferences for app-wide defaults (editable from the settings UI).
# Blank columns fall back to ENV / config.x.nyoy values.
class AppSetting < ApplicationRecord
  validate :connection_keys_must_be_available
  validate :sampling_preset_key_must_be_available

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

  private

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

  def validate_connection_key(attribute, keys)
    value = public_send(attribute).to_s.presence
    return if value.blank?
    return if keys.include?(value)

    errors.add(attribute, "は有効な接続を選んでください")
  end
end
