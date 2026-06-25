class AddHiresSettingsToImageGenerations < ActiveRecord::Migration[8.1]
  def change
    add_column :image_generations, :enable_hires, :boolean, null: false, default: true
    add_column :image_generations, :hires_upscaler, :string, null: false, default: "Latent"
    add_column :image_generations, :hires_scale, :float, null: false, default: 1.5
    add_column :image_generations, :hires_steps, :integer
    add_column :image_generations, :hires_denoising_strength, :float, null: false, default: 0.35
  end
end
