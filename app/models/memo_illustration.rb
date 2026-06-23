# frozen_string_literal: true

class MemoIllustration < ApplicationRecord
  belongs_to :prompt_skill

  has_one_attached :image

  STATUSES = %w[pending preparing planning generating completed failed].freeze

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
end
