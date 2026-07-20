# frozen_string_literal: true

class AddResearchPlannerModelToAppSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :app_settings, :research_planner_model_id, :string
  end
end
