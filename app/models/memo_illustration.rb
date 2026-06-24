# frozen_string_literal: true

class MemoIllustration < ApplicationRecord
  include GenerationProgressBroadcastable

  belongs_to :prompt_skill

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
  validates :sd_model, presence: true
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

  private

  def progress_panel_partial
    "memo_illustrations/status_panel"
  end

  def progress_panel_locals
    { memo_illustration: self }
  end
end
