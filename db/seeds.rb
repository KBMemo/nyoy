# frozen_string_literal: true

require_relative "../lib/prompt_skill_seeds"

PromptSkill.find_or_create_by!(name: "Stable Diffusion Prompt Engineer") do |skill|
  skill.body = PromptSkillSeeds::DEFAULT_BODY
  skill.default = true
end
