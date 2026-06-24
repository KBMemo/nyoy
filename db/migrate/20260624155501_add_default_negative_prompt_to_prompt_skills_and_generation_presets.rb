class AddDefaultNegativePromptToPromptSkillsAndGenerationPresets < ActiveRecord::Migration[8.1]
  def change
    add_column :prompt_skills, :default_negative_prompt, :text
    add_column :generation_presets, :default_negative_prompt, :text
  end
end
