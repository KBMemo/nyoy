# frozen_string_literal: true

class PromptSkill < ApplicationRecord
  has_many :memo_illustrations, dependent: :restrict_with_error
  has_many :generation_presets, dependent: :nullify

  validates :name, presence: true
  validates :body, presence: true

  before_save :clear_other_defaults, if: :default?

  scope :ordered, -> { order(default: :desc, name: :asc) }

  def self.default_for_generation
    find_by(default: true) || ordered.first
  end

  private

  def clear_other_defaults
    self.class.where(default: true).where.not(id: id).update_all(default: false)
  end
end
