# frozen_string_literal: true

class AddLlamaSwitchdBindingToServiceConnections < ActiveRecord::Migration[8.1]
  def change
    add_reference :service_connections,
                  :manager_connection,
                  foreign_key: { to_table: :service_connections },
                  index: false
    add_column :service_connections, :managed_server_id, :string
    add_index :service_connections,
              %i[manager_connection_id managed_server_id],
              name: "index_service_connections_on_manager_and_server"
  end
end
