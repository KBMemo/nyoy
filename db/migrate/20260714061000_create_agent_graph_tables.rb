# frozen_string_literal: true

class CreateAgentGraphTables < ActiveRecord::Migration[8.0]
  def change
    create_table :agent_runs do |t|
      t.references :chat, null: false, foreign_key: true
      t.string :graph_name, null: false, default: "research"
      t.string :status, null: false, default: "pending"
      t.string :current_node
      t.jsonb :state, null: false, default: {}
      t.text :error_message
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end
    add_index :agent_runs, :status
    add_index :agent_runs, :graph_name

    create_table :agent_checkpoints do |t|
      t.references :agent_run, null: false, foreign_key: true
      t.string :node_name, null: false
      t.jsonb :state, null: false, default: {}
      t.timestamps
    end
    add_index :agent_checkpoints, [ :agent_run_id, :created_at ]

    create_table :agent_node_runs do |t|
      t.references :agent_run, null: false, foreign_key: true
      t.string :node_name, null: false
      t.string :status, null: false, default: "pending"
      t.jsonb :input_snapshot, null: false, default: {}
      t.jsonb :output_snapshot, null: false, default: {}
      t.text :error_message
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end
    add_index :agent_node_runs, [ :agent_run_id, :node_name ]
  end
end
