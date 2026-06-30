# frozen_string_literal: true

class CreateImg2imgGenerations < ActiveRecord::Migration[8.0]
  def change
    create_table :img2img_generations do |t|
      t.string :aspect_ratio
      t.float :cfg_scale, null: false, default: 6.0
      t.float :denoising_strength, null: false, default: 0.55
      t.boolean :enable_hires, null: false, default: true
      t.text :error_message
      t.datetime :finished_at
      t.integer :height, null: false, default: 768
      t.float :hires_denoising_strength, null: false, default: 0.35
      t.float :hires_scale, null: false, default: 1.5
      t.integer :hires_steps
      t.string :hires_upscaler, null: false, default: "Latent"
      t.datetime :image_finished_at
      t.datetime :image_started_at
      t.text :japanese_prompt
      t.text :loras, null: false, default: "[]"
      t.text :negative_prompt
      t.text :prompt
      t.datetime :prompt_finished_at
      t.datetime :prompt_started_at
      t.jsonb :rag_source_chunk_ids, null: false, default: []
      t.bigint :render_preset_id
      t.jsonb :resolved_loras, null: false, default: []
      t.text :resolved_negative_prompt
      t.jsonb :resolved_params, null: false, default: {}
      t.string :sampler_name, null: false, default: "euler_a"
      t.string :sd_model
      t.integer :seed
      t.string :source_label
      t.datetime :started_at
      t.string :status, null: false, default: "pending"
      t.integer :steps, null: false, default: 22
      t.string :style_id
      t.boolean :use_source_dimensions, null: false, default: true
      t.boolean :vae_tiling, null: false, default: true
      t.integer :width, null: false, default: 768

      t.timestamps
    end

    add_index :img2img_generations, :render_preset_id
    add_index :img2img_generations, :style_id
    add_index :img2img_generations, :status
    add_foreign_key :img2img_generations, :render_presets
  end
end
