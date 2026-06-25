class AddDraftRefineWorkflowToImageGenerations < ActiveRecord::Migration[8.1]
  def change
    add_column :image_generations, :draft_batch_size, :integer, null: false, default: 4
    add_column :image_generations, :draft_steps, :integer
    add_column :image_generations, :refine_steps, :integer
    add_column :image_generations, :refine_denoising_strength, :float, null: false, default: 0.4
    add_column :image_generations, :selected_draft_index, :integer
  end
end
