# frozen_string_literal: true

class AddMemoKnowledgeCheckpointToAppSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :app_settings, :memo_knowledge_last_ingested_at, :datetime
  end
end
