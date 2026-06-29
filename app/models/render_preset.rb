# frozen_string_literal: true

# Render layer: a style-agnostic rendering pipeline.
#   single — memo illustration, one-shot (batch 1, no selection/refine)
#   draft  — image generation candidate pass (multi batch)
#   refine — finishing pass after selection (optional hires)
class RenderPreset < ApplicationRecord
  KINDS = %w[single draft refine].freeze
  KIND_LABELS = {
    "single" => "単発",
    "draft" => "案出し",
    "refine" => "本番"
  }.freeze

  validates :name, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :draft_batch_size,
    numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :draft_steps, :refine_steps, :hires_steps,
    numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 150 }, allow_nil: true
  validates :refine_denoising_strength, :hires_denoising_strength,
    numericality: { greater_than: 0, less_than_or_equal_to: 1 }, allow_nil: true
  validates :hires_scale,
    numericality: { greater_than: 1.0, less_than_or_equal_to: 4.0 }, allow_nil: true
  validates :hires_upscaler,
    inclusion: { in: ImageGeneration::HIRES_UPSCALERS }, if: -> { hires_upscaler.present? }

  before_save :clear_other_defaults, if: :default?

  scope :ordered, -> { order(default: :desc, name: :asc) }
  scope :of_kind, ->(kind) { where(kind: kind) }

  def self.default_for_kind(kind)
    of_kind(kind).where(default: true).first || of_kind(kind).ordered.first
  end

  KINDS.each do |kind_name|
    define_method("#{kind_name}?") { kind == kind_name }
  end

  def kind_label
    KIND_LABELS.fetch(kind, kind)
  end

  def apply_draft_to(generation)
    generation.assign_attributes(
      render_preset: self,
      draft_batch_size: draft_batch_size || 4,
      draft_steps: draft_steps
    )
  end

  def apply_refine_to(generation)
    generation.assign_attributes(
      refine_render_preset: self,
      refine_steps: refine_steps,
      refine_denoising_strength: refine_denoising_strength,
      enable_hires: enable_hires,
      hires_upscaler: hires_upscaler,
      hires_scale: hires_scale,
      hires_steps: hires_steps,
      hires_denoising_strength: hires_denoising_strength
    )
  end

  private

  def clear_other_defaults
    self.class.where(kind: kind, default: true).where.not(id: id).update_all(default: false)
  end
end
