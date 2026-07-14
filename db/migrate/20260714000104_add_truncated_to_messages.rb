# frozen_string_literal: true

class AddTruncatedToMessages < ActiveRecord::Migration[8.0]
  def change
    add_column :messages, :truncated, :boolean, default: false, null: false
  end
end
