# frozen_string_literal: true

class AddSeedKeyToServiceConnections < ActiveRecord::Migration[8.1]
  BUILTIN_KEYS = %w[
    llama_cpp
    gpt_oss
    openai
    vision_llama
    embeddings
    sd_cpp
    sd_switchd
    llama_switchd
    kbmemo
    tsuzura
    searfront
    readability
  ].freeze

  def up
    add_column :service_connections, :seed_key, :string
    add_index :service_connections, :seed_key, unique: true

    quoted_keys = BUILTIN_KEYS.map { |key| connection.quote(key) }.join(", ")
    execute <<~SQL.squish
      UPDATE service_connections
      SET seed_key = CASE
        WHEN legacy_key IN (#{quoted_keys}) THEN legacy_key
        WHEN key IN (#{quoted_keys}) THEN key
      END
      WHERE legacy_key IN (#{quoted_keys}) OR key IN (#{quoted_keys})
    SQL
  end

  def down
    remove_index :service_connections, :seed_key
    remove_column :service_connections, :seed_key
  end
end
