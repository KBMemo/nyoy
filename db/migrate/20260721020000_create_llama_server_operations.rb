# frozen_string_literal: true

class CreateLlamaServerOperations < ActiveRecord::Migration[8.1]
  def change
    create_table :llama_server_operations do |t|
      t.references :service_connection, null: false, foreign_key: true
      t.string :managed_server_id, null: false
      t.string :action, null: false
      t.string :status, null: false, default: "queued"
      t.jsonb :request_payload, null: false, default: {}
      t.jsonb :response_snapshot, null: false, default: {}
      t.text :error_message
      t.datetime :started_at
      t.datetime :finished_at

      t.timestamps
    end

    add_index :llama_server_operations,
              %i[service_connection_id managed_server_id],
              unique: true,
              where: "status IN ('queued', 'running')",
              name: "index_active_llama_server_operations"
    add_index :llama_server_operations, :created_at
  end
end
