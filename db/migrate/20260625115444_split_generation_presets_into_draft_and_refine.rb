class SplitGenerationPresetsIntoDraftAndRefine < ActiveRecord::Migration[8.1]
  def change
    change_table :generation_presets, bulk: true do |t|
      t.string :preset_kind, null: false, default: "draft"
      t.integer :draft_batch_size, null: false, default: 4
      t.integer :draft_steps
      t.integer :refine_steps
      t.float :refine_denoising_strength, null: false, default: 0.4
      t.boolean :enable_hires, null: false, default: true
      t.string :hires_upscaler, null: false, default: "Latent"
      t.float :hires_scale, null: false, default: 1.5
      t.integer :hires_steps
      t.float :hires_denoising_strength, null: false, default: 0.35
    end

    add_index :generation_presets, :preset_kind

    add_reference :image_generations, :refine_preset, null: true, foreign_key: { to_table: :generation_presets }
  end
end
