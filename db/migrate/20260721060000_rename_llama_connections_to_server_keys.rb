# frozen_string_literal: true

class RenameLlamaConnectionsToServerKeys < ActiveRecord::Migration[8.1]
  class Connection < ActiveRecord::Base
    self.table_name = "service_connections"
  end

  class ModelRecord < ActiveRecord::Base
    self.table_name = "models"
  end

  REFERENCE_COLUMNS = {
    "app_settings" => %w[default_chat_connection_key default_style_plan_connection_key],
    "image_generations" => %w[style_plan_connection_key],
    "img2img_generations" => %w[style_plan_connection_key],
    "memo_illustrations" => %w[style_plan_connection_key]
  }.freeze

  def up
    add_column :service_connections, :legacy_key, :string
    add_index :service_connections, :legacy_key, unique: true

    Connection.reset_column_information
    Connection.where(adapter: "llama_cpp").find_each do |record|
      old_key = record.key
      new_key = unique_key(record)
      rewrite_references(old_key, new_key)
      record.update_columns(key: new_key, legacy_key: old_key, updated_at: Time.current)
    end
  end

  def down
    Connection.reset_column_information
    Connection.where.not(legacy_key: nil).find_each do |record|
      rewrite_references(record.key, record.legacy_key)
      record.update_columns(key: record.legacy_key, legacy_key: nil, updated_at: Time.current)
    end
    remove_column :service_connections, :legacy_key
  end

  private

  def unique_key(record)
    source = record.managed_server_id.presence || record.server_model.presence || "connection-#{record.id}"
    base = "llama_server_#{source.downcase.gsub(/[^a-z0-9]+/, '_').gsub(/\A_+|_+\z/, '')}"
    candidate = base
    suffix = 2
    while Connection.where.not(id: record.id).exists?(key: candidate)
      candidate = "#{base}_#{suffix}"
      suffix += 1
    end
    candidate
  end

  def rewrite_references(old_key, new_key)
    REFERENCE_COLUMNS.each do |table, columns|
      columns.each do |column|
        execute <<~SQL.squish
          UPDATE #{quote_table_name(table)}
          SET #{quote_column_name(column)} = #{quote(new_key)}
          WHERE #{quote_column_name(column)} = #{quote(old_key)}
        SQL
      end
    end

    ModelRecord.where("metadata ->> 'connection_key' = ?", old_key).find_each do |model|
      model.update_columns(metadata: model.metadata.to_h.merge("connection_key" => new_key))
    end
  end
end
