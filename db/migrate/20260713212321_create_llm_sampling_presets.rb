# frozen_string_literal: true

class CreateLlmSamplingPresets < ActiveRecord::Migration[8.1]
  def change
    create_table :llm_sampling_presets do |t|
      t.string :key, null: false
      t.string :name, null: false
      t.text :notes
      t.jsonb :params, null: false, default: {}
      t.string :model_name_match
      t.boolean :builtin, null: false, default: false
      t.integer :sort_order, null: false, default: 0
      t.boolean :enabled, null: false, default: true

      t.timestamps
    end
    add_index :llm_sampling_presets, :key, unique: true
  end
end
