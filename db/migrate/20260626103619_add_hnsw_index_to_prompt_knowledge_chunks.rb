class AddHnswIndexToPromptKnowledgeChunks < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :prompt_knowledge_chunks, :embedding,
      using: :hnsw,
      opclass: :vector_cosine_ops,
      name: "index_prompt_knowledge_chunks_on_embedding_hnsw",
      algorithm: :concurrently
  end
end
