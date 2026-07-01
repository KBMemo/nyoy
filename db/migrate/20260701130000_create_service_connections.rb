# frozen_string_literal: true

class CreateServiceConnections < ActiveRecord::Migration[8.1]
  def change
    create_table :service_connections do |t|
      t.string :key, null: false
      t.string :name, null: false
      t.string :base_url, null: false
      t.string :server_model
      t.string :api_token
      t.boolean :enabled, null: false, default: true
      t.integer :sort_order, null: false, default: 0
      t.text :notes

      t.timestamps
    end

    add_index :service_connections, :key, unique: true
    add_index :service_connections, :enabled
  end
end
