# frozen_string_literal: true

class GenerationPreset < ApplicationRecord
  PRESET_KINDS = %w[draft refine].freeze
  PRESET_KIND_LABELS = {
    "draft" => "案出し",
    "refine" => "本番"
  }.freeze

  belongs_to :prompt_skill, optional: true
  has_many :image_generations, dependent: :nullify
  has_many :refined_image_generations,
    class_name: "ImageGeneration",
    foreign_key: :refine_preset_id,
    dependent: :nullify,
    inverse_of: :refine_preset

  validates :name, presence: true
  validates :sd_model, presence: true, unless: :refine?
  validates :preset_kind, inclusion: { in: PRESET_KINDS }
  validates :width, :height, numericality: { only_integer: true, greater_than: 0 }
  validates :steps, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 150 }
  validates :cfg_scale, numericality: { greater_than: 0, less_than_or_equal_to: 30 }
  validates :sampler_name, presence: true
  validates :loras, presence: true
  validates :draft_batch_size, numericality: { only_integer: true, in: 2..4 }, if: :draft?
  validates :refine_denoising_strength, numericality: { greater_than: 0, less_than_or_equal_to: 1 }, if: :refine?
  validates :hires_scale, numericality: { greater_than: 1.0, less_than_or_equal_to: 4.0 }, if: :refine?
  validates :hires_denoising_strength, numericality: { greater_than: 0, less_than_or_equal_to: 1 }, if: :refine?
  validates :hires_upscaler, inclusion: { in: ImageGeneration::HIRES_UPSCALERS }, if: :refine?

  before_validation :ensure_refine_base_attributes, if: :refine?
  before_save :clear_other_defaults, if: :default?

  scope :ordered, -> { order(default: :desc, name: :asc) }
  scope :draft, -> { where(preset_kind: "draft") }
  scope :refine, -> { where(preset_kind: "refine") }

  def self.default_for_generation
    default_for_kind("draft")
  end

  def self.default_for_kind(kind)
    where(preset_kind: kind, default: true).first || where(preset_kind: kind).ordered.first
  end

  def draft?
    preset_kind == "draft"
  end

  def refine?
    preset_kind == "refine"
  end

  def preset_kind_label
    PRESET_KIND_LABELS.fetch(preset_kind, preset_kind)
  end

  def loras_array
    JSON.parse(loras)
  rescue JSON::ParserError
    []
  end

  def loras_array=(entries)
    self.loras = JSON.generate(Array(entries))
  end

  def apply_to(generation)
    draft? ? apply_draft_to(generation) : apply_refine_to(generation)
  end

  def apply_draft_to(generation)
    generation.assign_attributes(
      generation_preset: self,
      prompt_skill: prompt_skill,
      sd_model: sd_model,
      width: width,
      height: height,
      steps: steps,
      cfg_scale: cfg_scale,
      sampler_name: sampler_name,
      vae_tiling: vae_tiling,
      loras: loras,
      draft_batch_size: draft_batch_size,
      draft_steps: draft_steps
    )
  end

  def apply_refine_to(generation)
    generation.assign_attributes(
      refine_preset: self,
      refine_steps: refine_steps,
      refine_denoising_strength: refine_denoising_strength,
      enable_hires: enable_hires,
      hires_upscaler: hires_upscaler,
      hires_scale: hires_scale,
      hires_steps: hires_steps,
      hires_denoising_strength: hires_denoising_strength
    )
  end

  def switch_lora_name
    loras_array.first&.fetch("name", nil)
  end

  def loras_for_api
    loras_array.filter_map do |entry|
      path = entry["path"].presence
      next if path.blank?

      {
        "path" => path,
        "multiplier" => entry.fetch("multiplier", 1.0).to_f
      }
    end
  end

  def resolved_default_negative_prompt
    NegativePromptResolver.base(skill: prompt_skill, preset: self)
  end

  private

  def clear_other_defaults
    self.class.where(preset_kind: preset_kind, default: true).where.not(id: id).update_all(default: false)
  end

  def ensure_refine_base_attributes
    self.loras = "[]" if loras.blank?
    self.sampler_name = "euler_a" if sampler_name.blank?
    self.width = 768 if width.blank? || width.to_i <= 0
    self.height = 768 if height.blank? || height.to_i <= 0
    self.steps = 22 if steps.blank? || steps.to_i <= 0
    self.cfg_scale = 6.0 if cfg_scale.blank? || cfg_scale.to_f <= 0
    self.vae_tiling = true if vae_tiling.nil?
    self.sd_model = "refine" if sd_model.blank?
  end
end
