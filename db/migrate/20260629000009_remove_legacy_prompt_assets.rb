# frozen_string_literal: true

class RemoveLegacyPromptAssets < ActiveRecord::Migration[8.1]
  def change
    remove_index :image_generations, :generation_preset_id, if_exists: true
    remove_index :image_generations, :refine_preset_id, if_exists: true
    remove_index :image_generations, :prompt_skill_id, if_exists: true
    remove_index :memo_illustrations, :prompt_skill_id, if_exists: true

    remove_column :image_generations, :generation_preset_id, :integer
    remove_column :image_generations, :refine_preset_id, :integer
    remove_column :image_generations, :prompt_skill_id, :integer
    remove_column :memo_illustrations, :prompt_skill_id, :integer

    drop_table :generation_presets, if_exists: true
    drop_table :prompt_presets, if_exists: true
    drop_table :prompt_loras, if_exists: true
    drop_table :prompt_skills, if_exists: true

    add_column :prompt_knowledge_chunks, :style_ref, :string
    add_index :prompt_knowledge_chunks, :style_ref
  end
end
