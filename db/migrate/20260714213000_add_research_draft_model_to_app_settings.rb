# frozen_string_literal: true

class AddResearchDraftModelToAppSettings < ActiveRecord::Migration[8.0]
  def change
    add_column :app_settings, :research_draft_model_id, :string
    add_column :app_settings, :research_draft_fallback, :string, default: "main", null: false
  end
end
