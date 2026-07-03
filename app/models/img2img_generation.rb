# frozen_string_literal: true

class Img2imgGeneration < ApplicationRecord
  include GenerationProgressBroadcastable
  include StylePlanConnectable

  has_one_attached :source_image
  has_one_attached :mask_image
  has_one_attached :sketch_image
  has_one_attached :image

  GENERATION_MODES = %w[img2img sketch inpaint inpaint_sketch inpaint_upload].freeze
  GENERATION_MODE_LABELS = {
    "img2img" => "img2img",
    "sketch" => "Sketch",
    "inpaint" => "Inpaint",
    "inpaint_sketch" => "Inpaint sketch",
    "inpaint_upload" => "Inpaint upload"
  }.freeze
  INPAINT_MODES = %w[inpaint inpaint_sketch inpaint_upload].freeze
  SKETCH_MODES = %w[sketch inpaint_sketch].freeze

  STATUSES = %w[pending preparing translating generating completed failed].freeze
  STATUS_LABELS = {
    "pending" => "待機中",
    "preparing" => "準備中",
    "translating" => "翻訳中",
    "generating" => "生成中",
    "completed" => "完了",
    "failed" => "失敗"
  }.freeze
  ASPECT_RATIOS = StylePlanJsonSchema::ASPECT_RATIOS
  ASPECT_RATIO_LABELS = ImageGeneration::ASPECT_RATIO_LABELS
  SOURCE_IMAGE_CONTENT_TYPES = %w[image/png image/jpeg image/webp].freeze
  DEFAULT_DENOISING_STRENGTH = 0.55

  validates :sd_model, presence: true, unless: :style_flow?
  validate :prompt_source_present
  validate :source_image_present, on: :create
  validates :status, inclusion: { in: STATUSES }
  validates :width, :height, numericality: { only_integer: true, greater_than: 0 }
  validates :steps, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 150 }
  validates :cfg_scale, numericality: { greater_than: 0, less_than_or_equal_to: 30 }
  validates :sampler_name, presence: true
  validates :loras, presence: true, unless: :style_flow?
  validates :denoising_strength, numericality: { greater_than: 0, less_than_or_equal_to: 1 }
  validates :aspect_ratio, inclusion: { in: ASPECT_RATIOS }, allow_blank: true
  validates :generation_mode, inclusion: { in: GENERATION_MODES }
  validate :source_image_content_type, if: -> { source_image.attached? }
  validate :mode_attachments_present, on: :create

  scope :recent, -> { order(created_at: :desc) }

  def self.aspect_ratio_options
    ASPECT_RATIO_LABELS.map { |value, label| [label, value] }
  end

  def self.generation_mode_options
    GENERATION_MODE_LABELS.map { |value, label| [label, value] }
  end

  def self.sd_aligned_dimension(value)
    ImageGeneration.sd_aligned_dimension(value)
  end

  def aspect_ratio_label
    return "おまかせ" if aspect_ratio.blank?

    ASPECT_RATIO_LABELS.fetch(aspect_ratio, aspect_ratio)
  end

  def in_progress?
    status.in?(%w[pending preparing translating generating])
  end

  def finished?
    status.in?(%w[completed failed])
  end

  def image_phase_active?
    in_progress? && status == "generating"
  end

  def loras_array
    JSON.parse(loras)
  rescue JSON::ParserError
    []
  end

  def loras_array=(entries)
    self.loras = JSON.generate(Array(entries))
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
      style_id: style_id,
      style_plan_connection_key: style_plan_connection_key,
      aspect_ratio: aspect_ratio,
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
      denoising_strength: denoising_strength,
      use_source_dimensions: use_source_dimensions,
      generation_mode: generation_mode
    )
  end

  def status_label
    STATUS_LABELS.fetch(status, status)
  end

  def display_summary
    japanese_prompt.presence || prompt.presence || source_label.presence || "—"
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

  def generation_mode_label
    GENERATION_MODE_LABELS.fetch(generation_mode, generation_mode)
  end

  def inpaint_mode?
    generation_mode.in?(INPAINT_MODES)
  end

  def sketch_mode?
    generation_mode.in?(SKETCH_MODES)
  end

  def rag_source_chunks
    PromptKnowledgeChunk.where(id: Array(rag_source_chunk_ids))
  end

  private

  def prompt_source_present
    return if japanese_prompt.present? || prompt.present?

    errors.add(:base, "日本語プロンプトまたは SD プロンプトを入力してください")
  end

  def source_image_present
    return if source_image.attached?

    errors.add(:source_image, "を選択してください")
  end

  def source_image_content_type
    return if SOURCE_IMAGE_CONTENT_TYPES.include?(source_image.content_type)

    errors.add(:source_image, "は PNG / JPEG / WebP にしてください")
  end

  def mode_attachments_present
    case generation_mode
    when "inpaint", "inpaint_sketch"
      errors.add(:base, "マスクを描いてください") unless mask_image.attached?
    when "inpaint_upload"
      errors.add(:mask_image, "を選択してください") unless mask_image.attached?
    when "sketch"
      errors.add(:base, "スケッチを描いてください") unless sketch_image.attached?
    when "inpaint_sketch"
      errors.add(:base, "スケッチを描いてください") unless sketch_image.attached?
      errors.add(:base, "マスクを描いてください") unless mask_image.attached?
    end
  end

  def progress_panel_partial
    "img2img_generations/status_panel"
  end

  def progress_panel_locals
    { img2img_generation: self }
  end
end
