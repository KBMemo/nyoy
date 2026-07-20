# frozen_string_literal: true

class AddAgentGraphIntentModelToAppSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :app_settings, :agent_graph_intent_model_id, :string
  end
end
