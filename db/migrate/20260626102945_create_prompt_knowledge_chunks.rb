class CreatePromptKnowledgeChunks < ActiveRecord::Migration[8.1]
  def change
    create_table :prompt_knowledge_chunks do |t|
      t.string :title, null: false
      t.text :body, null: false
      t.string :kind, null: false, default: "style"
      t.jsonb :metadata, null: false, default: {}
      t.vector :embedding, limit: 1024

      t.timestamps
    end

    add_index :prompt_knowledge_chunks, :kind
  end
end
