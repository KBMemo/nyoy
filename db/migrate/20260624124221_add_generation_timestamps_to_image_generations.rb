class AddGenerationTimestampsToImageGenerations < ActiveRecord::Migration[8.1]
  def change
    add_column :image_generations, :started_at, :datetime
    add_column :image_generations, :finished_at, :datetime
  end
end
