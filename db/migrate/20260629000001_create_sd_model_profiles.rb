class CreateSdModelProfiles < ActiveRecord::Migration[8.1]
  def change
    create_table :sd_model_profiles do |t|
      t.string  :key, null: false
      t.string  :name, null: false
      t.string  :family, null: false
      t.string  :switch_key, null: false
      t.string  :base_url
      t.jsonb   :default_params, null: false, default: {}
      t.boolean :enabled, null: false, default: true
      t.integer :sort_order, null: false, default: 0
      t.text    :notes

      t.timestamps
    end

    add_index :sd_model_profiles, :key, unique: true
    add_index :sd_model_profiles, :switch_key
  end
end
