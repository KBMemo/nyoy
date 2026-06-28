class CreatePromptStyleLoras < ActiveRecord::Migration[8.1]
  def change
    create_table :prompt_style_loras do |t|
      t.references :prompt_style, null: false, foreign_key: true
      t.references :lora_profile, null: false, foreign_key: true
      t.decimal    :multiplier, precision: 4, scale: 2, null: false, default: 0.7
      t.boolean    :required, null: false, default: false
      t.boolean    :inject_trigger_words, null: false, default: true
      t.integer    :sort_order, null: false, default: 0

      t.timestamps
    end

    add_index :prompt_style_loras, [:prompt_style_id, :lora_profile_id],
      unique: true, name: "index_prompt_style_loras_on_style_and_lora"
  end
end
