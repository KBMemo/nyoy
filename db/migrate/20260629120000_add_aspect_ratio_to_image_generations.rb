# frozen_string_literal: true

class AddAspectRatioToImageGenerations < ActiveRecord::Migration[8.1]
  def change
    add_column :image_generations, :aspect_ratio, :string
    add_index :image_generations, :aspect_ratio
  end
end
