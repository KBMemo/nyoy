class AllowNullJapanesePromptOnImageGenerations < ActiveRecord::Migration[8.1]
  def change
    change_column_null :image_generations, :japanese_prompt, true
  end
end
