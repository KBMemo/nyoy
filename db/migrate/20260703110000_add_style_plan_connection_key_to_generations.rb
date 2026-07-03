# frozen_string_literal: true

class AddStylePlanConnectionKeyToGenerations < ActiveRecord::Migration[8.1]
  def change
    add_column :image_generations, :style_plan_connection_key, :string
    add_column :memo_illustrations, :style_plan_connection_key, :string
    add_column :img2img_generations, :style_plan_connection_key, :string
  end
end
