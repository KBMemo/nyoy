# frozen_string_literal: true

require_relative "../lib/prompt_skill_seeds"
require_relative "../lib/generation_preset_seeds"
require_relative "../lib/rag_knowledge_seeds"
require_relative "../lib/capability_seeds"
require_relative "../lib/prompt_style_seeds"
require_relative "../lib/render_preset_seeds"

# Phase 1: capability layer (sd_model_profiles / lora_profiles).
CapabilitySeeds.seed!
# Phase 2: style layer (prompt_styles / prompt_style_models / prompt_style_loras).
PromptStyleSeeds.seed!
# Phase 3: render layer (render_presets).
RenderPresetSeeds.seed!

default_skill = PromptSkill.find_or_create_by!(name: "Stable Diffusion Prompt Engineer") do |record|
  record.body = PromptSkillSeeds::DEFAULT_BODY
  record.default = true
end
default_skill.update!(
  body: PromptSkillSeeds::DEFAULT_BODY,
  default_negative_prompt: PromptSkillSeeds::DEFAULT_NEGATIVE
)

chojugiga_json_skill = PromptSkill.find_or_create_by!(name: "鳥獣戯画プロンプト (JSON)") do |record|
  record.body = PromptSkillSeeds::CHOJUGIGA_JSON_BODY
  record.default = false
end

chojugiga_translator_skill = PromptSkill.find_or_create_by!(name: "鳥獣戯画プロンプト (翻訳)") do |record|
  record.body = PromptSkillSeeds::CHOJUGIGA_TRANSLATOR_BODY
  record.default = false
end

GenerationPreset.find_or_create_by!(name: "鳥獣戯画 (Illustrious + ChojuGiga)") do |preset|
  preset.preset_kind = "draft"
  preset.sd_model = "pony-v6"
  preset.width = 768
  preset.height = 768
  preset.steps = 22
  preset.cfg_scale = 6.0
  preset.sampler_name = "euler_a"
  preset.vae_tiling = true
  preset.loras_array = GenerationPresetSeeds::CHOJUGIGA_LORAS
  preset.prompt_skill = chojugiga_translator_skill
  preset.draft_batch_size = 4
  preset.default = true
end

GenerationPreset.find_or_create_by!(name: "鳥獣戯画 本番") do |preset|
  preset.preset_kind = "refine"
  preset.sd_model = "pony-v6"
  preset.width = 768
  preset.height = 768
  preset.steps = 22
  preset.cfg_scale = 6.0
  preset.sampler_name = "euler_a"
  preset.vae_tiling = true
  preset.loras = "[]"
  preset.refine_denoising_strength = 0.4
  preset.enable_hires = true
  preset.hires_upscaler = "Latent"
  preset.hires_scale = 1.5
  preset.hires_denoising_strength = 0.35
  preset.default = true
end

preset = GenerationPreset.find_by(name: "鳥獣戯画 (Illustrious + ChojuGiga)")
preset&.update!(
  preset_kind: "draft",
  draft_batch_size: 4,
  prompt_skill: chojugiga_translator_skill,
  default_negative_prompt: GenerationPresetSeeds::CHOJUGIGA_DEFAULT_NEGATIVE
)

refine_preset = GenerationPreset.find_by(name: "鳥獣戯画 本番")
refine_preset&.update!(
  preset_kind: "refine",
  refine_denoising_strength: 0.4,
  enable_hires: true,
  hires_upscaler: "Latent",
  hires_scale: 1.5,
  hires_denoising_strength: 0.35,
  default: true
)

chojugiga_json_skill.update!(
  body: PromptSkillSeeds::CHOJUGIGA_JSON_BODY,
  default_negative_prompt: PromptSkillSeeds::DEFAULT_NEGATIVE
)
chojugiga_translator_skill.update!(
  body: PromptSkillSeeds::CHOJUGIGA_TRANSLATOR_BODY,
  default_negative_prompt: PromptSkillSeeds::DEFAULT_NEGATIVE
)

[
  {
    title: "鳥獣戯画の線画と余白",
    kind: "style",
    body: <<~BODY.strip
      chojugiga, emaki, ink outline, minimal background, playful animals.
      線画を優先し、背景は余白多め。現代的な彩色や3D表現は避ける。
    BODY
  },
  {
    title: "ChojuGiga LoRA",
    kind: "lora",
    body: <<~BODY.strip
      LoRA名: ChojuGiga_Illustrious
      trigger: chojugiga
      推奨 weight: 0.7〜0.9
      pony-v6 / Illustrious 系で使用。
    BODY
  },
  {
    title: "鳥獣戯画向けネガティブ",
    kind: "negative",
    body: RagKnowledgeSeeds::CHOJUGIGA_NEGATIVE_GUIDANCE
  }
].each do |attrs|
  chunk = PromptKnowledgeChunk.find_or_create_by!(title: attrs[:title]) do |record|
    record.kind = attrs[:kind]
    record.body = attrs[:body]
  end
  chunk.update!(kind: attrs[:kind], body: attrs[:body])
end

PromptLora.find_or_create_by!(name: "ChojuGiga_Illustrious") do |record|
  record.path = "chojugiga/ChojuGiga_Illustrious.safetensors"
  record.trigger_words = "chojugiga, emaki"
  record.compatible_models_list = ["pony-v6"]
  record.weight_min = 0.7
  record.weight_max = 0.9
  record.notes = "鳥獣戯画 LoRA。Illustrious / pony 系向け。"
end

PromptPreset.find_or_create_by!(name: "鳥獣戯画テンプレ") do |record|
  record.model_family = "pony"
  record.positive_template = "masterpiece, best quality, chojugiga, emaki, ink outline, minimal background"
  record.negative_template = RagKnowledgeSeeds::CHOJUGIGA_NEGATIVE_TEMPLATE
  record.default_params = { "steps" => 22, "cfg_scale" => 6.0 }
end
