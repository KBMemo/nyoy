# frozen_string_literal: true

class ImageGeneration < ApplicationRecord
  has_one_attached :image

  STATUSES = %w[pending preparing translating generating completed failed].freeze

  validates :japanese_prompt, presence: true
  validates :sd_model, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :width, :height, numericality: { only_integer: true, greater_than: 0 }
  validates :steps, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 150 }
  validates :cfg_scale, numericality: { greater_than: 0, less_than_or_equal_to: 30 }

  scope :recent, -> { order(created_at: :desc) }

  def in_progress?
    status.in?(%w[pending preparing translating generating])
  end

  def finished?
    status.in?(%w[completed failed])
  end
end
