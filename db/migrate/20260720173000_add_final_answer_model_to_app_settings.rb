# frozen_string_literal: true

class AddFinalAnswerModelToAppSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :app_settings, :final_answer_model_id, :string
  end
end
