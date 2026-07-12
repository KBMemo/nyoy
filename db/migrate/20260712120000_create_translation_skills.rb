# frozen_string_literal: true

class CreateTranslationSkills < ActiveRecord::Migration[8.0]
  def change
    create_table :translation_skills do |t|
      t.string :name, null: false
      t.text :body, null: false
      t.string :family
      t.references :sd_model_profile, foreign_key: true, null: true
      t.boolean :enabled, null: false, default: true
      t.integer :sort_order, null: false, default: 0
      t.text :notes

      t.timestamps
    end

    add_index :translation_skills, :family
    add_index :translation_skills, %i[enabled sort_order]
  end
end
