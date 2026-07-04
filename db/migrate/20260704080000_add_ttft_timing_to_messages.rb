class AddTtftTimingToMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :messages, :context_build_elapsed_ms, :integer
    add_column :messages, :first_chunk_elapsed_ms, :integer
  end
end
