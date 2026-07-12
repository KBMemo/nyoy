# frozen_string_literal: true

class RenameTranslationSkillsToSdPromptTemplates < ActiveRecord::Migration[8.0]
  def change
    rename_table :translation_skills, :sd_prompt_templates
  end
end
