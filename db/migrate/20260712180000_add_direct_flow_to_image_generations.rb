# frozen_string_literal: true

class AddDirectFlowToImageGenerations < ActiveRecord::Migration[8.0]
  def change
    add_column :image_generations, :generation_flow, :string, null: false, default: "draft"
    add_reference :image_generations, :sd_model_profile, foreign_key: true, null: true
    add_reference :image_generations, :sd_prompt_template, foreign_key: true, null: true

    add_index :image_generations, :generation_flow
  end
end
