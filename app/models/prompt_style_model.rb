# frozen_string_literal: true

# Join: a style offers a model, one of which is the style default.
class PromptStyleModel < ApplicationRecord
  belongs_to :prompt_style
  belongs_to :sd_model_profile

  validates :sd_model_profile_id, uniqueness: { scope: :prompt_style_id }

  before_save :clear_other_defaults, if: :default?

  scope :ordered, -> { order(sort_order: :asc) }

  private

  def clear_other_defaults
    PromptStyleModel
      .where(prompt_style_id: prompt_style_id, default: true)
      .where.not(id: id)
      .update_all(default: false)
  end
end
