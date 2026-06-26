class CreatePromptPresets < ActiveRecord::Migration[8.1]
  def change
    create_table :prompt_presets do |t|
      t.string :name, null: false
      t.string :model_family, null: false
      t.text :positive_template
      t.text :negative_template
      t.jsonb :default_params, null: false, default: {}

      t.timestamps
    end

    add_index :prompt_presets, :name, unique: true
    add_index :prompt_presets, :model_family
  end
end
