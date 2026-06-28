# frozen_string_literal: true

# Join: a style applies a LoRA at a given multiplier.
class PromptStyleLora < ApplicationRecord
  belongs_to :prompt_style
  belongs_to :lora_profile

  validates :lora_profile_id, uniqueness: { scope: :prompt_style_id }
  validates :multiplier, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 2 }

  scope :ordered, -> { order(sort_order: :asc) }

  def to_lora_entry
    {
      "name" => lora_profile.name,
      "path" => lora_profile.path,
      "multiplier" => multiplier.to_f
    }.compact
  end
end
