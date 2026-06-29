# frozen_string_literal: true

class MemoIllustration < ApplicationRecord
  include GenerationProgressBroadcastable

  has_one_attached :image

  STATUSES = %w[pending preparing planning generating completed failed].freeze
  STATUS_LABELS = {
    "pending" => "待機中",
    "preparing" => "準備中",
    "planning" => "計画中",
    "generating" => "生成中",
    "completed" => "完了",
    "failed" => "失敗"
  }.freeze

  validates :body, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :width, :height, numericality: { only_integer: true, greater_than: 0 }
  validates :steps, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 150 }
  validates :cfg_scale, numericality: { greater_than: 0, less_than_or_equal_to: 30 }

  scope :recent, -> { order(created_at: :desc) }

  def in_progress?
    status.in?(%w[pending preparing planning generating])
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

  private

  def progress_panel_partial
    "memo_illustrations/status_panel"
  end

  def progress_panel_locals
    { memo_illustration: self }
  end
end
