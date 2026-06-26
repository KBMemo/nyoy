class CreatePromptLoras < ActiveRecord::Migration[8.1]
  def change
    create_table :prompt_loras do |t|
      t.string :name, null: false
      t.string :path
      t.text :trigger_words
      t.string :compatible_models, array: true, null: false, default: []
      t.float :weight_min, null: false, default: 0.0
      t.float :weight_max, null: false, default: 1.0
      t.text :notes

      t.timestamps
    end

    add_index :prompt_loras, :name, unique: true
  end
end
