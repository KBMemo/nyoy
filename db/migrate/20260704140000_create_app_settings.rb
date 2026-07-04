# frozen_string_literal: true

class CreateAppSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :app_settings do |t|
      t.string :default_chat_connection_key
      t.string :default_style_plan_connection_key

      t.timestamps
    end
  end
end
