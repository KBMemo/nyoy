class AddGenerationTimestampsToMemoIllustrations < ActiveRecord::Migration[8.1]
  def change
    add_column :memo_illustrations, :started_at, :datetime
    add_column :memo_illustrations, :finished_at, :datetime
  end
end
