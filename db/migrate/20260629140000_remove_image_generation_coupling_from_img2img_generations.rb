# frozen_string_literal: true

class RemoveImageGenerationCouplingFromImg2imgGenerations < ActiveRecord::Migration[8.0]
  def change
    remove_reference :img2img_generations, :render_preset, foreign_key: true
    remove_column :img2img_generations, :enable_hires, :boolean
    remove_column :img2img_generations, :hires_denoising_strength, :float
    remove_column :img2img_generations, :hires_scale, :float
    remove_column :img2img_generations, :hires_steps, :integer
    remove_column :img2img_generations, :hires_upscaler, :string
  end
end
