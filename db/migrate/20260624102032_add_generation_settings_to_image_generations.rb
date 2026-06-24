class AddGenerationSettingsToImageGenerations < ActiveRecord::Migration[8.1]
  def change
    add_reference :image_generations, :generation_preset, null: true, foreign_key: true
    add_reference :image_generations, :prompt_skill, null: true, foreign_key: true
    add_column :image_generations, :sampler_name, :string, null: false, default: "euler_a"
    add_column :image_generations, :vae_tiling, :boolean, null: false, default: false
    add_column :image_generations, :loras, :text, null: false, default: "[]"
  end
end
