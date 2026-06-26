class AddRagFieldsToImageGenerations < ActiveRecord::Migration[8.1]
  def change
    add_column :image_generations, :prompt_spec, :jsonb
    add_column :image_generations, :rag_source_chunk_ids, :jsonb, default: [], null: false
  end
end
