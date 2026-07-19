# frozen_string_literal: true

class AddAgentGraphRoleProfilesToAppSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :app_settings, :agent_graph_role_profiles, :jsonb, default: {}, null: false
  end
end
