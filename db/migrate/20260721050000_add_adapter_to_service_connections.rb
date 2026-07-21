# frozen_string_literal: true

class AddAdapterToServiceConnections < ActiveRecord::Migration[8.1]
  LOCAL_MODEL_KEYS = %w[llama_cpp gpt_oss vision_llama embeddings].freeze

  def up
    add_column :service_connections, :adapter, :string, null: false, default: "generic"
    execute <<~SQL.squish
      UPDATE service_connections
      SET adapter = CASE
        WHEN key = 'openai' THEN 'openai'
        WHEN key = 'llama_switchd' THEN 'llama_switchd'
        WHEN key IN (#{LOCAL_MODEL_KEYS.map { |key| connection.quote(key) }.join(', ')})
          OR key LIKE 'llm\_%' ESCAPE '\\' THEN 'llama_cpp'
        ELSE 'generic'
      END
    SQL
    add_index :service_connections, :adapter
  end

  def down
    remove_column :service_connections, :adapter
  end
end
