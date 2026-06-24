# frozen_string_literal: true

require_relative "../lib/prompt_skill_seeds"
require_relative "../lib/generation_preset_seeds"

PromptSkill.find_or_create_by!(name: "Stable Diffusion Prompt Engineer") do |record|
  record.body = PromptSkillSeeds::DEFAULT_BODY
  record.default = true
end

chojugiga_json_skill = PromptSkill.find_or_create_by!(name: "鳥獣戯画プロンプト (JSON)") do |record|
  record.body = PromptSkillSeeds::CHOJUGIGA_JSON_BODY
  record.default = false
end

chojugiga_translator_skill = PromptSkill.find_or_create_by!(name: "鳥獣戯画プロンプト (翻訳)") do |record|
  record.body = PromptSkillSeeds::CHOJUGIGA_TRANSLATOR_BODY
  record.default = false
end

GenerationPreset.find_or_create_by!(name: "鳥獣戯画 (Illustrious + ChojuGiga)") do |preset|
  preset.sd_model = "pony-v6"
  preset.width = 768
  preset.height = 768
  preset.steps = 22
  preset.cfg_scale = 6.0
  preset.sampler_name = "euler_a"
  preset.vae_tiling = true
  preset.loras_array = GenerationPresetSeeds::CHOJUGIGA_LORAS
  preset.prompt_skill = chojugiga_translator_skill
  preset.default = true
end

preset = GenerationPreset.find_by(name: "鳥獣戯画 (Illustrious + ChojuGiga)")
preset&.update!(prompt_skill: chojugiga_translator_skill)

chojugiga_json_skill.update!(body: PromptSkillSeeds::CHOJUGIGA_JSON_BODY)
chojugiga_translator_skill.update!(body: PromptSkillSeeds::CHOJUGIGA_TRANSLATOR_BODY)
