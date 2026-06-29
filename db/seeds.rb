# frozen_string_literal: true

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
    record.style_ref = attrs[:style_ref]
  end
  chunk.update!(kind: attrs[:kind], body: attrs[:body], style_ref: attrs[:style_ref])
end
