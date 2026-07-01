class AddTimingToMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :messages, :response_elapsed_ms, :integer
    add_column :messages, :thinking_elapsed_ms, :integer
  end
end
