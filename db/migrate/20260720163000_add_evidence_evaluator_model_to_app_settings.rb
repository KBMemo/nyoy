# frozen_string_literal: true

class AddEvidenceEvaluatorModelToAppSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :app_settings, :evidence_evaluator_model_id, :string
  end
end
