# frozen_string_literal: true

# Style layer: the look of a generation, keyed by style_id.
# Holds the fixed positive prefix/suffix, the single fixed negative prompt,
# generation defaults, and the allowed override ranges. Models and LoRAs are
# wired through join tables so a style can offer several models.
class PromptStyle < ApplicationRecord
  has_many :prompt_style_models, dependent: :destroy
  has_many :sd_model_profiles, through: :prompt_style_models
  has_many :prompt_style_loras, dependent: :destroy
  has_many :lora_profiles, through: :prompt_style_loras

  validates :style_id, :name, :prompt_prefix, presence: true
  validates :style_id, uniqueness: true
  validate :exactly_one_default_model, if: -> { prompt_style_models.any? }

  scope :enabled, -> { where(enabled: true) }
  scope :ordered, -> { order(sort_order: :asc, name: :asc) }

  def referenced?
    return @_referenced if defined?(@_referenced)

    @_referenced = MemoIllustration.exists?(style_id: style_id) ||
                   ImageGeneration.exists?(style_id: style_id) ||
                   PromptKnowledgeChunk.exists?(style_ref: style_id)
  end

  def aliases_text
    Array(aliases).join(", ")
  end

  def aliases_text=(value)
    self.aliases = value.to_s.split(/[,、\n]/).map(&:strip).reject(&:blank?)
  end

  def generation_defaults_json
    JSON.pretty_generate(generation_defaults.presence || {})
  end

  def generation_defaults_json=(value)
    assign_json_field(:generation_defaults, value)
  end

  def allowed_overrides_json
    JSON.pretty_generate(allowed_overrides.presence || {})
  end

  def allowed_overrides_json=(value)
    assign_json_field(:allowed_overrides, value)
  end

  def aspect_presets_json
    JSON.pretty_generate(aspect_presets.presence || {})
  end

  def aspect_presets_json=(value)
    assign_json_field(:aspect_presets, value)
  end

  def default_style_model
    prompt_style_models.detect(&:default?) || prompt_style_models.min_by(&:sort_order)
  end

  def default_model
    default_style_model&.sd_model_profile
  end

  # Architecture family (sd15/sdxl/pony/illustrious/sd35/flux) of the default
  # model, used to steer family-specific prompt guidance and params.
  def family
    default_model&.family
  end

  def style_model_for(model_key)
    return default_style_model if model_key.blank?

    prompt_style_models.detect { |sm| sm.sd_model_profile&.key == model_key }
  end

  def aspect_dimensions(aspect_ratio)
    aspect_presets[aspect_ratio.to_s] || aspect_presets[aspect_presets.keys.first]
  end

  private

  def assign_json_field(attribute, value)
    text = value.to_s.strip
    self[attribute] = text.blank? ? {} : JSON.parse(text)
  rescue JSON::ParserError
    errors.add(attribute, "must be valid JSON")
  end

  def exactly_one_default_model
    defaults = prompt_style_models.select(&:default?).size
    errors.add(:base, "style には既定モデルを 1 つ指定してください") unless defaults == 1
  end
end
