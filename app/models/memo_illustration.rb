# frozen_string_literal: true

class MemoIllustration < ApplicationRecord
  include GenerationProgressBroadcastable

  has_one_attached :image
  has_many_attached :inpainted_images

  STATUSES = %w[pending preparing planning generating inpainting completed failed].freeze
  STATUS_LABELS = {
    "pending" => "待機中",
    "preparing" => "準備中",
    "planning" => "計画中",
    "generating" => "生成中",
    "inpainting" => "部分修正中",
    "completed" => "完了",
    "failed" => "失敗"
  }.freeze

  DEFAULT_INPAINT_DENOISING_STRENGTH = 0.55
  STALE_INPAINT_WAIT = 2.minutes
  MAX_INPAINT_WAIT = 30.minutes

  validates :body, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :width, :height, numericality: { only_integer: true, greater_than: 0 }
  validates :steps, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 150 }
  validates :cfg_scale, numericality: { greater_than: 0, less_than_or_equal_to: 30 }
  validate :style_id_must_be_enabled

  scope :recent, -> { order(created_at: :desc) }

  def in_progress?
    status.in?(%w[pending preparing planning generating inpainting])
  end

  def inpaintable?
    return false if in_progress?
    return false unless image.attached?

    status.in?(%w[completed failed])
  end

  def inpaint_job_runnable?
    return false unless image.attached?

    status.in?(%w[completed failed inpainting])
  end

  def recover_stale_inpaint!(submitted: false)
    return unless status == "inpainting"
    return unless image_started_at

    threshold = submitted ? MAX_INPAINT_WAIT.ago : STALE_INPAINT_WAIT.ago
    return if image_started_at > threshold

    update!(
      status: inpainted_images.attached? ? "completed" : "failed",
      error_message: error_message.presence || "前回の部分修正が完了しませんでした",
      image_finished_at: Time.current
    )
  end

  def inpainted_image_attachments
    inpainted_images.attachments.sort_by(&:created_at).reverse
  end

  def latest_inpaint_source_attachment
    inpainted_image_attachments.first || image_attachment
  end

  def default_inpaint_source_attachment
    image_attachment
  end

  def latest_display_attachment
    latest_inpaint_source_attachment
  end

  def inpainted_image_label(attachment)
    sequence = attachment.metadata["sequence"] || inpainted_image_attachments.size
    "修正版 #{sequence}"
  end

  def build_inpaint_prompt(delta:, include_prefix: false, include_suffix: false)
    parts = []
    style = prompt_style

    if include_prefix && style&.prompt_prefix.present?
      parts << style.prompt_prefix.strip
    end

    delta_text = delta.to_s.strip
    parts << delta_text if delta_text.present?

    if include_suffix && style&.prompt_suffix.present?
      parts << style.prompt_suffix.strip
    end

    prompt = parts.compact_blank.join(", ")
    raise "部分修正プロンプトが空です" if prompt.blank?

    prompt
  end

  def inpaint_prompt_for(attachment)
    attachment.metadata["inpaint_prompt"].presence
  end

  def inpaint_note_for(attachment)
    attachment.metadata["inpaint_note"].presence
  end

  def inpaint_note_translated_for(attachment)
    attachment.metadata["inpaint_note_translated"].presence
  end

  def inpaint_include_prefix_for(attachment)
    cast_metadata_boolean(attachment.metadata["inpaint_include_prefix"])
  end

  def inpaint_include_suffix_for(attachment)
    cast_metadata_boolean(attachment.metadata["inpaint_include_suffix"])
  end

  def inpaint_prompt_breakdown_for(attachment)
    style = prompt_style
    {
      prefix: inpaint_include_prefix_for(attachment) ? style&.prompt_prefix&.strip.presence : nil,
      delta: inpaint_note_translated_for(attachment),
      suffix: inpaint_include_suffix_for(attachment) ? style&.prompt_suffix&.strip.presence : nil,
      full: inpaint_prompt_for(attachment)
    }
  end

  def inpainted_attachment?(attachment)
    inpainted_images.attachments.any? { |item| item.id == attachment.id }
  end

  def image_phase_active?
    in_progress? && status.in?(%w[generating inpainting])
  end

  def finished?
    status.in?(%w[completed failed])
  end

  def status_label
    STATUS_LABELS.fetch(status, status)
  end

  def resolved_negative_prompt
    snapshot = self[:resolved_negative_prompt]
    return snapshot if snapshot.present?

    negative_prompt.to_s.strip
  end

  def prompt_style
    return if style_id.blank?

    @prompt_style ||= PromptStyle.find_by(style_id: style_id)
  end

  def style_label
    prompt_style&.name || style_id.presence
  end

  def loras_for_api
    Array(resolved_loras).filter_map do |entry|
      path = entry["path"].presence
      next if path.blank?

      { "path" => path, "multiplier" => entry.fetch("multiplier", 1.0).to_f }
    end
  end

  def rag_source_chunks
    PromptKnowledgeChunk.where(id: Array(rag_source_chunk_ids))
  end

  def apply_form_settings_to(illustration)
    illustration.assign_attributes(
      body: body,
      style_id: style_id
    )
  end

  def broadcast_progress_panel
    super

    locals = inpaint_panel_locals
    return if locals[:source_attachment].blank?

    broadcast_replace_to(
      self,
      target: ActionView::RecordIdentifier.dom_id(self, :inpaint),
      partial: "memo_illustrations/inpaint_panel",
      locals: locals
    )
  end

  def inpaint_panel_locals
    {
      memo_illustration: self,
      source_attachment: default_inpaint_source_attachment,
      prompt_style: prompt_style
    }
  end

  private

  def style_id_must_be_enabled
    return if style_id.blank?
    return if PromptStyle.enabled.exists?(style_id: style_id)

    errors.add(:style_id, "は有効なスタイルを指定してください")
  end

  def cast_metadata_boolean(value)
    return nil if value.nil?

    ActiveModel::Type::Boolean.new.cast(value)
  end

  def progress_panel_partial
    "memo_illustrations/status_panel"
  end

  def progress_panel_locals
    { memo_illustration: self }
  end
end
