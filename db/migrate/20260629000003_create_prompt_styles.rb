class CreatePromptStyles < ActiveRecord::Migration[8.1]
  def change
    create_table :prompt_styles do |t|
      t.string  :style_id, null: false
      t.string  :name, null: false
      t.text    :description
      t.text    :prompt_prefix, null: false
      t.text    :prompt_suffix
      t.text    :negative_prompt, null: false, default: ""
      t.jsonb   :generation_defaults, null: false, default: {}
      t.jsonb   :allowed_overrides, null: false, default: {}
      t.jsonb   :aspect_presets, null: false, default: {}
      t.jsonb   :aliases, null: false, default: []
      t.boolean :enabled, null: false, default: true
      t.integer :sort_order, null: false, default: 0

      t.timestamps
    end

    add_index :prompt_styles, :style_id, unique: true
  end
end
