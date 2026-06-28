class CreateRenderPresets < ActiveRecord::Migration[8.1]
  def change
    create_table :render_presets do |t|
      t.string  :name, null: false
      t.string  :kind, null: false
      t.boolean :default, null: false, default: false

      # single / draft
      t.integer :draft_batch_size
      t.integer :draft_steps

      # refine
      t.integer :refine_steps
      t.decimal :refine_denoising_strength, precision: 4, scale: 3
      t.boolean :enable_hires, null: false, default: false
      t.string  :hires_upscaler
      t.decimal :hires_scale, precision: 4, scale: 2
      t.integer :hires_steps
      t.decimal :hires_denoising_strength, precision: 4, scale: 3

      t.timestamps
    end

    add_index :render_presets, :kind
    add_index :render_presets, [:kind, :default]
  end
end
