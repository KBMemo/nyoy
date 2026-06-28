# frozen_string_literal: true

# Capability layer: a Stable Diffusion model that sd.cpp / switchd can serve.
# Holds only the definition; prompt/look concerns live in PromptStyle.
class SdModelProfile < ApplicationRecord
  FAMILIES = %w[sd15 sdxl pony illustrious flux].freeze

  validates :key, :name, :family, :switch_key, presence: true
  validates :key, uniqueness: true
  validates :family, inclusion: { in: FAMILIES }

  scope :enabled, -> { where(enabled: true) }
  scope :ordered, -> { order(sort_order: :asc, name: :asc) }

  def default_params_json
    JSON.pretty_generate(default_params.presence || {})
  end

  def default_params_json=(value)
    self.default_params = value.to_s.strip.blank? ? {} : JSON.parse(value)
  rescue JSON::ParserError
    errors.add(:default_params, "must be valid JSON")
  end
end
