class CreateLoraProfiles < ActiveRecord::Migration[8.1]
  def change
    create_table :lora_profiles do |t|
      t.string  :key, null: false
      t.string  :name, null: false
      t.string  :family
      t.string  :path, null: false
      t.string  :trigger_words, array: true, null: false, default: []
      t.decimal :default_multiplier, precision: 4, scale: 2, null: false, default: 0.7
      t.decimal :min_multiplier, precision: 4, scale: 2, null: false, default: 0.0
      t.decimal :max_multiplier, precision: 4, scale: 2, null: false, default: 1.5
      t.boolean :enabled, null: false, default: true
      t.text    :notes

      t.timestamps
    end

    add_index :lora_profiles, :key, unique: true
    add_index :lora_profiles, :path, unique: true
  end
end
