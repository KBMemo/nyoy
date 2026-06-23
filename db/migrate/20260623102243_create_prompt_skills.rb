class CreatePromptSkills < ActiveRecord::Migration[8.1]
  def change
    create_table :prompt_skills do |t|
      t.string :name, null: false
      t.text :body, null: false
      t.boolean :default, null: false, default: false

      t.timestamps
    end

    add_index :prompt_skills, :default
  end
end
