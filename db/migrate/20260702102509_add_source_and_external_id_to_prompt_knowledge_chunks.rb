# frozen_string_literal: true

class AddSourceAndExternalIdToPromptKnowledgeChunks < ActiveRecord::Migration[8.1]
  def change
    add_column :prompt_knowledge_chunks, :source, :string, null: false, default: "prompt"
    add_column :prompt_knowledge_chunks, :external_id, :string

    add_index :prompt_knowledge_chunks, :source
    add_index :prompt_knowledge_chunks, :external_id, unique: true, where: "external_id IS NOT NULL"
  end
end
