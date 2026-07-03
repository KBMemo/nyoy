# frozen_string_literal: true

class AddSettingsToServiceConnections < ActiveRecord::Migration[8.0]
  def change
    add_column :service_connections, :settings, :jsonb, null: false, default: {}
  end
end
