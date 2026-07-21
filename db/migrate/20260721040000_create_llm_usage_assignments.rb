# frozen_string_literal: true

class CreateLlmUsageAssignments < ActiveRecord::Migration[8.1]
  def change
    create_table :llm_usage_assignments do |t|
      t.string :usage_key, null: false
      t.references :model, null: false, foreign_key: true
      t.references :fallback_model, foreign_key: { to_table: :models }
      t.references :llm_sampling_preset, foreign_key: { on_delete: :nullify }
      t.boolean :enabled, null: false, default: true

      t.timestamps
    end

    add_index :llm_usage_assignments, :usage_key, unique: true
  end
end
