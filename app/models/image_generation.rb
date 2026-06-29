# frozen_string_literal: true

class ImageGeneration < ApplicationRecord
  include GenerationProgressBroadcastable

  belongs_to :render_preset, optional: true
  belongs_to :refine_render_preset, class_name: "RenderPreset", optional: true

  has_one_attached :image
  has_many_attached :drafts
  has_many_attached :refined_images

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
  HIRES_UPSCALERS = %w[Latent Latent\ (nearest-exact) Lanczos Nearest].freeze

  validates :sd_model, presence: true, unless: :style_flow?
  validate :prompt_source_present
  validates :status, inclusion: { in: STATUSES }
  validates :width, :height, numericality: { only_integer: true, greater_than: 0 }
  validates :steps, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 150 }
  validates :cfg_scale, numericality: { greater_than: 0, less_than_or_equal_to: 30 }
  validates :sampler_name, presence: true
  validates :loras, presence: true, unless: :style_flow?
  validates :draft_batch_size, numericality: { only_integer: true, in: 2..4 }
  validates :refine_denoising_strength, numericality: { greater_than: 0, less_than_or_equal_to: 1 }
  validates :draft_steps, allow_nil: true, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 150 }
  validates :refine_steps, allow_nil: true, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 150 }
  validates :hires_scale, numericality: { greater_than: 1.0, less_than_or_equal_to: 4.0 }
  validates :hires_denoising_strength, numericality: { greater_than: 0, less_than_or_equal_to: 1 }
  validates :hires_steps, allow_nil: true, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 150 }
  validates :hires_upscaler, inclusion: { in: HIRES_UPSCALERS }

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

  def refineable?
    return false if in_progress?
    return false unless drafts.attached?

    awaiting_selection? || status.in?(%w[completed failed])
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

  def refined_image_attachments
    refined_images.attachments.sort_by(&:created_at).reverse
  end

  def latest_refined_attachment
    attachment = refined_image_attachments.first
    return attachment if attachment
    return image if image.attached?

    nil
  end

  def refined_image_label(attachment)
    sequence = attachment.metadata["sequence"] || refined_image_attachments.size
    draft_index = attachment.metadata["draft_index"]
    label = "仕上がり #{sequence}"
    label += " · ラフ案 #{draft_index.to_i + 1}" unless draft_index.nil?
    label
  end

  def hires_steps_for_api
    hires_steps.presence || refine_steps_for_api
  end

  def hires_target_width
    (width * hires_scale).round
  end

  def hires_target_height
    (height * hires_scale).round
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
    if resolved_loras.present?
      return Array(resolved_loras).filter_map do |entry|
        path = entry["path"].presence
        next if path.blank?

        { "path" => path, "multiplier" => entry.fetch("multiplier", 1.0).to_f }
      end
    end

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
      render_preset: render_preset,
      refine_render_preset: refine_render_preset,
      style_id: style_id,
      japanese_prompt: japanese_prompt,
      prompt: prompt,
      negative_prompt: negative_prompt,
      resolved_negative_prompt: resolved_negative_prompt,
      resolved_loras: resolved_loras,
      resolved_params: resolved_params,
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
      refine_denoising_strength: refine_denoising_strength,
      enable_hires: enable_hires,
      hires_upscaler: hires_upscaler,
      hires_scale: hires_scale,
      hires_steps: hires_steps,
      hires_denoising_strength: hires_denoising_strength
    )
  end

  def status_label
    STATUS_LABELS.fetch(status, status)
  end

  def display_summary
    japanese_prompt.presence || prompt.presence || "—"
  end

  def resolved_negative_prompt
    snapshot = self[:resolved_negative_prompt]
    return snapshot if snapshot.present?

    NegativePromptResolver.for_generation(self)
  end

  def prompt_style
    return if style_id.blank?

    @prompt_style ||= PromptStyle.find_by(style_id: style_id)
  end

  def style_label
    prompt_style&.name || style_id.presence
  end

  def style_flow?
    style_id.present? || japanese_prompt.present?
  end

  def rag_source_chunks
    PromptKnowledgeChunk.where(id: Array(rag_source_chunk_ids))
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
