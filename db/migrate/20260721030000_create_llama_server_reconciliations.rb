# frozen_string_literal: true

class CreateLlamaServerReconciliations < ActiveRecord::Migration[8.1]
  def change
    create_table :llama_server_reconciliations do |t|
      t.references :service_connection, null: false, foreign_key: true
      t.string :status, null: false
      t.jsonb :findings, null: false, default: []
      t.jsonb :server_snapshot, null: false, default: []
      t.text :error_message
      t.datetime :checked_at, null: false

      t.timestamps
    end

    add_index :llama_server_reconciliations, :checked_at
  end
end
