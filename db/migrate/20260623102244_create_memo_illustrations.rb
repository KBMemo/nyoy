class CreateMemoIllustrations < ActiveRecord::Migration[8.1]
  def change
    create_table :memo_illustrations do |t|
      t.text :body, null: false
      t.text :positive_prompt
      t.text :negative_prompt
      t.string :sd_model, null: false
      t.integer :width, null: false, default: 512
      t.integer :height, null: false, default: 512
      t.integer :steps, null: false, default: 20
      t.float :cfg_scale, null: false, default: 7.0
      t.integer :seed
      t.string :status, null: false, default: "pending"
      t.text :error_message
      t.text :llama_raw_response
      t.references :prompt_skill, null: false, foreign_key: true

      t.timestamps
    end
  end
end
