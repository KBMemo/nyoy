class AddStyleFieldsToImageGenerations < ActiveRecord::Migration[8.1]
  def change
    add_column :image_generations, :style_id, :string
    add_column :image_generations, :resolved_negative_prompt, :text
    add_column :image_generations, :resolved_loras, :jsonb, null: false, default: []
    add_column :image_generations, :resolved_params, :jsonb, null: false, default: {}

    add_reference :image_generations, :render_preset, foreign_key: true
    add_reference :image_generations, :refine_render_preset, foreign_key: { to_table: :render_presets }

    add_index :image_generations, :style_id

    change_column_null :image_generations, :prompt_skill_id, true
    change_column_null :image_generations, :sd_model, true
  end
end
