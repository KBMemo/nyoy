# frozen_string_literal: true

class AddResponseStateToChats < ActiveRecord::Migration[8.1]
  def change
    add_column :chats, :response_state, :string, null: false, default: "idle"
    add_index :chats, :response_state
  end
end
