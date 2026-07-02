# frozen_string_literal: true

class AddContextSummaryToChats < ActiveRecord::Migration[8.1]
  def change
    add_column :chats, :context_summary, :text
    add_column :chats, :context_summary_until_message_id, :bigint
    add_index :chats, :context_summary_until_message_id
  end
end
