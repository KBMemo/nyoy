# frozen_string_literal: true

class AddGenerationModeToImg2imgGenerations < ActiveRecord::Migration[8.0]
  def change
    add_column :img2img_generations, :generation_mode, :string, default: "img2img", null: false
  end
end
