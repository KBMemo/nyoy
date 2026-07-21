# frozen_string_literal: true

class LlmUsageAssignment < ApplicationRecord
  belongs_to :model
  belongs_to :fallback_model, class_name: "Model", optional: true
  belongs_to :llm_sampling_preset, optional: true

  validates :usage_key, presence: true, uniqueness: true, inclusion: { in: ->(_) { LlmUsageCatalog.keys } }
  validate :models_must_support_usage
  validate :fallback_model_must_differ

  scope :enabled, -> { where(enabled: true) }

  def definition
    LlmUsageCatalog.fetch(usage_key)
  end

  private

  def models_must_support_usage
    return if usage_key.blank? || !LlmUsageCatalog.keys.include?(usage_key)

    validate_model_capabilities(:model, model)
    validate_model_capabilities(:fallback_model, fallback_model) if fallback_model
  end

  def validate_model_capabilities(attribute, candidate)
    return unless candidate

    missing = definition.capabilities - LlmModelCapabilities.for(candidate)
    return if missing.empty?

    errors.add(attribute, "は必要な能力を満たしていません: #{missing.join(', ')}")
  end

  def fallback_model_must_differ
    return if model_id.blank? || fallback_model_id.blank? || model_id != fallback_model_id

    errors.add(:fallback_model, "は主モデルと異なるモデルを選択してください")
  end
end
