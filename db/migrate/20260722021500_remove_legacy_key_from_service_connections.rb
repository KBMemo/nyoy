# frozen_string_literal: true

class RemoveLegacyKeyFromServiceConnections < ActiveRecord::Migration[8.1]
  REFERENCE_COLUMNS = {
    image_generations: :style_plan_connection_key,
    img2img_generations: :style_plan_connection_key,
    memo_illustrations: :style_plan_connection_key
  }.freeze

  def up
    legacy_keys = connection.select_values(<<~SQL.squish)
      SELECT legacy_key FROM service_connections WHERE legacy_key IS NOT NULL
    SQL
    ensure_no_legacy_references!(legacy_keys)

    remove_index :service_connections, :legacy_key
    remove_column :service_connections, :legacy_key
  end

  def down
    add_column :service_connections, :legacy_key, :string
    add_index :service_connections, :legacy_key, unique: true
  end

  private

  def ensure_no_legacy_references!(legacy_keys)
    return if legacy_keys.empty?

    values = legacy_keys.map { |key| connection.quote(key) }.join(", ")
    references = REFERENCE_COLUMNS.filter_map do |table, column|
      count = connection.select_value(<<~SQL.squish).to_i
        SELECT COUNT(*) FROM #{connection.quote_table_name(table)}
        WHERE #{connection.quote_column_name(column)} IN (#{values})
      SQL
      "#{table}.#{column}=#{count}" if count.positive?
    end
    return if references.empty?

    raise ActiveRecord::MigrationError,
          "legacy ServiceConnection key references remain: #{references.join(', ')}"
  end
end
