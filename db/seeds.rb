# frozen_string_literal: true

require_relative "../lib/rag_knowledge_seeds"
require_relative "../lib/capability_seeds"
require_relative "../lib/prompt_style_seeds"
require_relative "../lib/render_preset_seeds"
require_relative "../lib/sd_prompt_template_seeds"
require_relative "../lib/llm_sampling_preset_seeds"
require_relative "../lib/llm_usage_assignment_seeds"

# Phase 1: capability layer (sd_model_profiles / lora_profiles).
CapabilitySeeds.seed!
# Parameter-tab: family-level prompt generation templates.
SdPromptTemplateSeeds.seed!
# Phase 2: style layer (prompt_styles / prompt_style_models / prompt_style_loras).
PromptStyleSeeds.seed!
# Phase 3: render layer (render_presets).
RenderPresetSeeds.seed!
ServiceConnectionSeeds.seed!
ChatModelSeeds.seed!
LlmSamplingPresetSeeds.seed!
LlmUsageAssignmentSeeds.seed!

skip_prompt_knowledge_embedding = ENV["SKIP_PROMPT_KNOWLEDGE_EMBEDDING"].present?

[
  {
    title: "鳥獣戯画の線画と余白",
    kind: "style",
    style_ref: "chojugiga_emaki",
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
      pony-v6 / Illustrious 系で使用（Illustrious 推奨）。
    BODY
  },
  {
    title: "鳥獣戯画向けネガティブ",
    kind: "negative",
    body: RagKnowledgeSeeds::CHOJUGIGA_NEGATIVE_GUIDANCE
  },
  {
    title: "括弧を使った強調構文の使い方",
    kind: "emphasis",
    body: RagKnowledgeSeeds::EMPHASIS_SYNTAX_GUIDANCE
  },
  {
    title: "水彩静物画の構図とタッチ",
    kind: "style",
    style_ref: "watercolor_still_life",
    body: <<~BODY.strip
      watercolor still life, soft wash, table top objects, cafe items, cups, books, flowers.
      テーブル上の日常品を主題に。人物は原則なし。余白と紙の質感を活かす。
      カフェラテ、ノート、カーテンなど静かな室内シーンに向く。
    BODY
  },
  {
    title: "水彩静物画向けネガティブ",
    kind: "negative",
    style_ref: "watercolor_still_life",
    body: <<~BODY.strip
      photorealistic, 3d, anime, character focus, human focus, busy background,
      harsh contrast, digital sharpness, neon colors, cluttered scene
    BODY
  },
  {
    title: InpaintNoteTranslator::SKILL_TITLE,
    kind: "inpaint",
    body: <<~BODY.squish
      You translate Japanese inpainting correction notes into short English Stable Diffusion prompt fragments.
      The user is fixing only a masked region of an existing image via img2img inpaint.
      Output comma-separated English tags and short phrases describing the corrected detail only.
      Focus on anatomy, hands, fingers, objects, textures, and local fixes.
      Do not rewrite the whole scene. Do not add quality tags unless the note asks for them.
      Output only the English fragment with no explanation, quotes, or markdown.
      Examples:
      - 手を自然に、指をはっきり → natural hands, detailed fingers, correct anatomy
      - ボールの模様をはっきり → clear soccer ball pattern, sharp pentagon panels
      - 生ビールのグラスを追加 → draft beer glass, foam, condensation
    BODY
  }
].each do |attrs|
  chunk = PromptKnowledgeChunk.find_or_create_by!(title: attrs[:title]) do |record|
    record.skip_auto_embed = skip_prompt_knowledge_embedding
    record.kind = attrs[:kind]
    record.body = attrs[:body]
    record.style_ref = attrs[:style_ref]
  end
  chunk.skip_auto_embed = skip_prompt_knowledge_embedding
  chunk.update!(kind: attrs[:kind], body: attrs[:body], style_ref: attrs[:style_ref])
end
