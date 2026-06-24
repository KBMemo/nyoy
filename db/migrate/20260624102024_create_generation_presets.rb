class CreateGenerationPresets < ActiveRecord::Migration[8.1]
  def change
    create_table :generation_presets do |t|
      t.string :name, null: false
      t.string :sd_model, null: false
      t.integer :width, null: false, default: 768
      t.integer :height, null: false, default: 768
      t.integer :steps, null: false, default: 22
      t.float :cfg_scale, null: false, default: 6.0
      t.string :sampler_name, null: false, default: "euler_a"
      t.boolean :vae_tiling, null: false, default: true
      t.text :loras, null: false, default: "[]"
      t.boolean :default, null: false, default: false
      t.references :prompt_skill, null: true, foreign_key: true

      t.timestamps
    end

    add_index :generation_presets, :default
  end
end
