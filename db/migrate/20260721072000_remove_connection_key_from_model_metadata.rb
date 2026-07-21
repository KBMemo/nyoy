# frozen_string_literal: true

class RemoveConnectionKeyFromModelMetadata < ActiveRecord::Migration[8.1]
  def up
    orphan_count = select_value(<<~SQL.squish).to_i
      SELECT COUNT(*) FROM models
      WHERE metadata ? 'connection_key' AND service_connection_id IS NULL
    SQL
    if orphan_count.positive?
      raise ActiveRecord::MigrationError,
            "cannot remove Model metadata connection_key: #{orphan_count} models have no service connection"
    end

    execute "UPDATE models SET metadata = metadata - 'connection_key' WHERE metadata ? 'connection_key'"
  end

  def down
    execute <<~SQL.squish
      UPDATE models
      SET metadata = jsonb_set(metadata, '{connection_key}', to_jsonb(service_connections.key))
      FROM service_connections
      WHERE models.service_connection_id = service_connections.id
    SQL
  end
end
