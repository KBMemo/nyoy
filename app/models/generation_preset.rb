# frozen_string_literal: true

class GenerationPreset < ApplicationRecord
  belongs_to :prompt_skill, optional: true
  has_many :image_generations, dependent: :nullify

  validates :name, :sd_model, presence: true
  validates :width, :height, numericality: { only_integer: true, greater_than: 0 }
  validates :steps, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 150 }
  validates :cfg_scale, numericality: { greater_than: 0, less_than_or_equal_to: 30 }
  validates :sampler_name, presence: true
  validates :loras, presence: true

  before_save :clear_other_defaults, if: :default?

  scope :ordered, -> { order(default: :desc, name: :asc) }

  def self.default_for_generation
    find_by(default: true) || ordered.first
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
    generation.assign_attributes(
      generation_preset: self,
      prompt_skill: prompt_skill,
      negative_prompt: NegativePromptResolver.resolve(skill: prompt_skill, preset: self),
      sd_model: sd_model,
      width: width,
      height: height,
      steps: steps,
      cfg_scale: cfg_scale,
      sampler_name: sampler_name,
      vae_tiling: vae_tiling,
      loras: loras
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
    NegativePromptResolver.resolve(skill: prompt_skill, preset: self)
  end

  private

  def clear_other_defaults
    self.class.where(default: true).where.not(id: id).update_all(default: false)
  end
end
