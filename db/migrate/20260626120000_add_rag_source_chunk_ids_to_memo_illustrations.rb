# frozen_string_literal: true

class AddRagSourceChunkIdsToMemoIllustrations < ActiveRecord::Migration[8.1]
  def change
    add_column :memo_illustrations, :rag_source_chunk_ids, :jsonb, default: [], null: false
  end
end
