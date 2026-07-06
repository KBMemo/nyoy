class AddLlmParamsToChats < ActiveRecord::Migration[8.1]
  def change
    add_column :chats, :llm_params, :jsonb, default: {}, null: false
  end
end
