# frozen_string_literal: true

# Capability layer: a LoRA that sd.cpp can load.
# Holds only the definition; style ↔ lora wiring lives in PromptStyleLora.
class LoraProfile < ApplicationRecord
  validates :key, :name, :path, presence: true
  validates :key, :path, uniqueness: true
  validates :default_multiplier, :min_multiplier, :max_multiplier,
    numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 2 }
  validate :multiplier_range_valid

  scope :enabled, -> { where(enabled: true) }
  scope :ordered, -> { order(name: :asc) }

  def trigger_words_list
    Array(trigger_words).reject(&:blank?)
  end

  def trigger_words_list=(values)
    self.trigger_words = split_values(values)
  end

  private

  def split_values(values)
    list = values.is_a?(Array) ? values : values.to_s.split(",")
    list.map { |value| value.to_s.strip }.reject(&:blank?)
  end

  def multiplier_range_valid
    return if min_multiplier.blank? || max_multiplier.blank?
    return if min_multiplier <= max_multiplier

    errors.add(:max_multiplier, "must be greater than or equal to min_multiplier")
  end
end
