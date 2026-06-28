class AddStyleFieldsToMemoIllustrations < ActiveRecord::Migration[8.1]
  def change
    add_column :memo_illustrations, :style_id, :string
    add_column :memo_illustrations, :resolved_negative_prompt, :text
    add_column :memo_illustrations, :resolved_loras, :jsonb, null: false, default: []
    add_column :memo_illustrations, :resolved_params, :jsonb, null: false, default: {}

    add_index :memo_illustrations, :style_id

    # Style flow resolves the model/skill server-side, so they are no longer
    # required at creation time.
    change_column_null :memo_illustrations, :prompt_skill_id, true
    change_column_null :memo_illustrations, :sd_model, true
  end
end
