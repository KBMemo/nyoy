# frozen_string_literal: true

# Capability layer: a Stable Diffusion model that sd.cpp / switchd can serve.
# Holds only the definition; prompt/look concerns live in PromptStyle.
class SdModelProfile < ApplicationRecord
  FAMILIES = %w[sd15 sdxl pony illustrious sd35 flux].freeze
  FAMILY_LABELS = {
    "sd15" => "SD 1.5",
    "sdxl" => "SDXL",
    "pony" => "Pony",
    "illustrious" => "Illustrious",
    "sd35" => "SD 3.5",
    "flux" => "Flux"
  }.freeze

  # Base generation params per architecture family. A profile's own
  # default_params (if any) is deep-merged on top of these, so family provides
  # sensible defaults while individual models can still override.
  FAMILY_DEFAULT_PARAMS = {
    "sd15"        => { "width" => 512, "height" => 512, "steps" => 20, "cfg_scale" => 7.0, "sampler_name" => "euler_a" },
    "sdxl"        => { "width" => 768, "height" => 768, "steps" => 24, "cfg_scale" => 6.0, "sampler_name" => "euler_a" },
    "pony"        => { "width" => 768, "height" => 768, "steps" => 24, "cfg_scale" => 6.0, "sampler_name" => "euler_a" },
    "illustrious" => { "width" => 768, "height" => 768, "steps" => 24, "cfg_scale" => 6.0, "sampler_name" => "euler_a" },
    "sd35"        => { "width" => 1024, "height" => 1024, "steps" => 28, "cfg_scale" => 4.5, "sampler_name" => "euler" },
    "flux"        => { "width" => 1024, "height" => 1024, "steps" => 20, "cfg_scale" => 1.0, "sampler_name" => "euler" }
  }.freeze

  has_many :prompt_style_models, dependent: :restrict_with_error
  has_many :sd_prompt_templates, dependent: :destroy

  validates :key, :name, :family, :switch_key, presence: true
  validates :key, uniqueness: true
  validates :family, inclusion: { in: FAMILIES }

  scope :enabled, -> { where(enabled: true) }
  scope :ordered, -> { order(sort_order: :asc, name: :asc) }

  def family_label
    FAMILY_LABELS.fetch(family, family)
  end

  def family_default_params
    FAMILY_DEFAULT_PARAMS.fetch(family, {})
  end

  # Family base params with this profile's own overrides applied on top.
  def resolved_default_params
    family_default_params.deep_merge(default_params.to_h)
  end

  def linked_to_styles?
    prompt_style_models.exists?
  end

  def default_params_json
    JSON.pretty_generate(default_params.presence || {})
  end

  def default_params_json=(value)
    self.default_params = value.to_s.strip.blank? ? {} : JSON.parse(value)
  rescue JSON::ParserError
    errors.add(:default_params, "must be valid JSON")
  end
end
