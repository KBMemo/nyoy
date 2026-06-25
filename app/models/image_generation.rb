# frozen_string_literal: true

class ImageGeneration < ApplicationRecord
  include GenerationProgressBroadcastable

  belongs_to :generation_preset, optional: true
  belongs_to :prompt_skill, optional: true

  has_one_attached :image
  has_many_attached :drafts

  STATUSES = %w[
    pending preparing translating drafting awaiting_selection refining completed failed
  ].freeze
  STATUS_LABELS = {
    "pending" => "待機中",
    "preparing" => "準備中",
    "translating" => "翻訳中",
    "drafting" => "ラフ生成中",
    "awaiting_selection" => "案選択待ち",
    "refining" => "仕上げ中",
    "completed" => "完了",
    "failed" => "失敗"
  }.freeze

  validates :sd_model, presence: true
  validate :prompt_source_present
  validates :status, inclusion: { in: STATUSES }
  validates :width, :height, numericality: { only_integer: true, greater_than: 0 }
  validates :steps, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 150 }
  validates :cfg_scale, numericality: { greater_than: 0, less_than_or_equal_to: 30 }
  validates :sampler_name, presence: true
  validates :loras, presence: true
  validates :draft_batch_size, numericality: { only_integer: true, in: 2..4 }
  validates :refine_denoising_strength, numericality: { greater_than: 0, less_than_or_equal_to: 1 }
  validates :draft_steps, allow_nil: true, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 150 }
  validates :refine_steps, allow_nil: true, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 150 }

  scope :recent, -> { order(created_at: :desc) }

  def in_progress?
    status.in?(%w[pending preparing translating drafting refining])
  end

  def finished?
    status.in?(%w[completed failed])
  end

  def awaiting_selection?
    status == "awaiting_selection"
  end

  def image_phase_active?
    in_progress? && status.in?(%w[drafting refining])
  end

  def draft_steps_for_api
    draft_steps.presence || [steps, 18].min
  end

  def refine_steps_for_api
    refine_steps.presence || steps
  end

  def loras_array
    JSON.parse(loras)
  rescue JSON::ParserError
    []
  end

  def loras_array=(entries)
    self.loras = JSON.generate(Array(entries))
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

  def apply_settings_to(generation)
    generation.assign_attributes(
      generation_preset: generation_preset,
      prompt_skill: prompt_skill,
      japanese_prompt: japanese_prompt,
      prompt: prompt,
      negative_prompt: negative_prompt,
      sd_model: sd_model,
      width: width,
      height: height,
      steps: steps,
      cfg_scale: cfg_scale,
      seed: seed,
      sampler_name: sampler_name,
      vae_tiling: vae_tiling,
      loras: loras,
      draft_batch_size: draft_batch_size,
      draft_steps: draft_steps,
      refine_steps: refine_steps,
      refine_denoising_strength: refine_denoising_strength
    )
  end

  def status_label
    STATUS_LABELS.fetch(status, status)
  end

  def display_summary
    japanese_prompt.presence || prompt.presence || "—"
  end

  private

  def prompt_source_present
    return if japanese_prompt.present? || prompt.present?

    errors.add(:base, "日本語プロンプトまたは SD プロンプトを入力してください")
  end

  def progress_panel_partial
    "image_generations/status_panel"
  end

  def progress_panel_locals
    { image_generation: self }
  end
end
