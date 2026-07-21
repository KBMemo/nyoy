# frozen_string_literal: true

class AddServiceConnectionToModels < ActiveRecord::Migration[8.1]
  def up
    add_reference :models, :service_connection, foreign_key: { on_delete: :nullify }, index: true

    execute <<~SQL.squish
      UPDATE models
      SET service_connection_id = service_connections.id
      FROM service_connections
      WHERE models.metadata ->> 'connection_key' IN (service_connections.key, service_connections.legacy_key)
    SQL
  end

  def down
    remove_reference :models, :service_connection, foreign_key: true, index: true
  end
end
