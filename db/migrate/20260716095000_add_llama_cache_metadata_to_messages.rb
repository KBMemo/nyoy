# frozen_string_literal: true

class AddLlamaCacheMetadataToMessages < ActiveRecord::Migration[8.0]
  def change
    add_column :messages, :llama_cache_prompt, :boolean
    add_column :messages, :llama_cache_slot_id, :integer
    add_column :messages, :llama_cache_slot_count, :integer
  end
end
