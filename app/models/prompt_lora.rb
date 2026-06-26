# frozen_string_literal: true

class PromptLora < ApplicationRecord
  validates :name, presence: true, uniqueness: true
  validates :weight_min, :weight_max, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 2 }
  validate :weight_range_valid

  scope :ordered, -> { order(name: :asc) }
  scope :for_model, ->(model) { where("? = ANY(compatible_models)", model) if model.present? }

  def compatible_models_list
    Array(compatible_models).reject(&:blank?)
  end

  def compatible_models_list=(values)
    self.compatible_models = Array(values).map(&:to_s).map(&:strip).reject(&:blank?)
  end

  def default_weight
    ((weight_min + weight_max) / 2.0).round(2)
  end

  def to_rag_context
    lines = ["LoRA: #{name}"]
    lines << "path: #{path}" if path.present?
    lines << "trigger: #{trigger_words}" if trigger_words.present?
    lines << "models: #{compatible_models_list.join(", ")}" if compatible_models_list.any?
    lines << "weight: #{weight_min}..#{weight_max}"
    lines << notes if notes.present?
    lines.join("\n")
  end

  def to_lora_entry(weight: nil)
    {
      "name" => name,
      "path" => path,
      "multiplier" => (weight || default_weight).to_f
    }.compact
  end

  private

  def weight_range_valid
    return if weight_min.blank? || weight_max.blank?
    return if weight_min <= weight_max

    errors.add(:weight_max, "must be greater than or equal to weight_min")
  end
end
