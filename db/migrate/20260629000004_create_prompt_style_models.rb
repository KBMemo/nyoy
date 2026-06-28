class CreatePromptStyleModels < ActiveRecord::Migration[8.1]
  def change
    create_table :prompt_style_models do |t|
      t.references :prompt_style, null: false, foreign_key: true
      t.references :sd_model_profile, null: false, foreign_key: true
      t.boolean    :default, null: false, default: false
      t.jsonb      :param_overrides, null: false, default: {}
      t.integer    :sort_order, null: false, default: 0

      t.timestamps
    end

    add_index :prompt_style_models, [:prompt_style_id, :sd_model_profile_id],
      unique: true, name: "index_prompt_style_models_on_style_and_model"
  end
end
