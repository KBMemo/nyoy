# frozen_string_literal: true

class CreateMemoRagWebhookEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :memo_rag_webhook_events do |t|
      t.string :event_id, null: false
      t.string :event_type, null: false
      t.bigint :account_id, null: false
      t.string :memo_uid, null: false
      t.bigint :memo_id
      t.datetime :memo_updated_at
      t.datetime :occurred_at, null: false
      t.string :status, null: false, default: "pending"
      t.text :error_message
      t.datetime :processed_at
      t.timestamps

      t.index :event_id, unique: true
      t.index [ :status, :created_at ]
      t.index :memo_uid
    end
  end
end
