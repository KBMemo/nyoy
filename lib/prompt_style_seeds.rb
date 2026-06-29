# frozen_string_literal: true

# Phase 2 (style layer) seeds. Rebuilds legacy preset/skill content as style_id-keyed PromptStyle rows.
module PromptStyleSeeds
  CHOJUGIGA_DEFAULT_NEGATIVE = [
    "worst quality, low quality, blurry, photorealistic, photo, 3d, modern, colorful, vibrant colors, detailed background, anime cel shading, human focus",
    "text, letters, words, writing, calligraphy, kanji, hiragana, katakana, alphabet, caption, subtitle, watermark, signature, artist signature, seal, red seal, stamp, hanko, inkan, monogram, logo, inscription, speech bubble, manga text, scroll text, poem text"
  ].join(", ").freeze

  XL_DEFAULTS = {
    "width" => 768, "height" => 768, "steps" => 22,
    "cfg_scale" => 6.0, "sampler_name" => "euler_a"
  }.freeze

  XL_ASPECTS = {
    "square" => { "width" => 768, "height" => 768 },
    "portrait" => { "width" => 768, "height" => 1024 },
    "landscape" => { "width" => 1024, "height" => 768 }
  }.freeze

  XL_OVERRIDES = {
    "steps" => { "min" => 16, "max" => 32 },
    "cfg_scale" => { "min" => 4.5, "max" => 8.0 }
  }.freeze

  STYLES = [
    {
      style_id: "chojugiga_emaki",
      name: "鳥獣戯画",
      description: "鳥獣戯画（emaki / sumi-e）風の墨線イラスト。背景は余白多め、擬人化された動物が動的に振る舞う。",
      prompt_prefix: "chojugiga, emaki, scroll painting, ink wash painting, sumi-e, " \
        "japanese medieval art, yamato-e, monochrome, minimal background, dynamic pose, humorous",
      prompt_suffix: "ink brush strokes, bold ink lines",
      negative_prompt: CHOJUGIGA_DEFAULT_NEGATIVE,
      generation_defaults: XL_DEFAULTS,
      aspect_presets: XL_ASPECTS,
      allowed_overrides: XL_OVERRIDES,
      aliases: ["鳥獣戯画", "鳥獣人物戯画", "chojugiga", "emaki", "墨絵"],
      sort_order: 0,
      models: [
        { key: "pony-v6", default: true },
        { key: "illustrious_pencil-XL", default: false }
      ],
      loras: [
        { key: "chojugiga_illustrious", multiplier: 0.8, required: false }
      ]
    },
    {
      style_id: "pencil_still_life_sketch",
      name: "鉛筆の静物スケッチ風",
      description: "落ち着いた鉛筆デッサン風の静物画。モノクロ、白い紙の背景、簡素な構図。",
      prompt_prefix: "pencil still life sketch, monochrome, greyscale, traditional media, " \
        "graphite pencil drawing, hand drawn, rough graphite shading, soft cross hatching, " \
        "white paper background, simple composition, calm mood, natural light, subtle shadows",
      prompt_suffix: "quiet atmosphere, minimal background",
      negative_prompt: "color, colorful, photorealistic, 3d render, glossy, digital painting, " \
        "character focus, cluttered background, complex background",
      generation_defaults: XL_DEFAULTS,
      aspect_presets: XL_ASPECTS,
      allowed_overrides: XL_OVERRIDES,
      aliases: ["鉛筆スケッチ", "静物デッサン", "pencil sketch", "still life sketch", "graphite drawing"],
      sort_order: 1,
      models: [
        { key: "illustrious_pencil-XL", default: true }
      ],
      loras: []
    }
  ].freeze

  module_function

  def seed!
    STYLES.each { |attrs| upsert_style!(attrs) }
  end

  def upsert_style!(attrs)
    style = PromptStyle.find_or_initialize_by(style_id: attrs[:style_id])
    style.assign_attributes(
      name: attrs[:name],
      description: attrs[:description],
      prompt_prefix: attrs[:prompt_prefix],
      prompt_suffix: attrs[:prompt_suffix],
      negative_prompt: attrs[:negative_prompt],
      generation_defaults: attrs[:generation_defaults],
      aspect_presets: attrs[:aspect_presets],
      allowed_overrides: attrs[:allowed_overrides],
      aliases: attrs[:aliases],
      sort_order: attrs[:sort_order],
      enabled: true
    )
    style.save!(validate: false)

    sync_models!(style, attrs[:models])
    sync_loras!(style, attrs[:loras])
    style.save! # re-validate with the default-model rule satisfied
    style
  end

  def sync_models!(style, models)
    Array(models).each_with_index do |spec, index|
      profile = SdModelProfile.find_by!(key: spec[:key])
      link = PromptStyleModel.find_or_initialize_by(prompt_style: style, sd_model_profile: profile)
      link.assign_attributes(default: spec[:default], sort_order: index)
      link.save!
    end
  end

  def sync_loras!(style, loras)
    Array(loras).each_with_index do |spec, index|
      profile = LoraProfile.find_by!(key: spec[:key])
      link = PromptStyleLora.find_or_initialize_by(prompt_style: style, lora_profile: profile)
      link.assign_attributes(
        multiplier: spec[:multiplier],
        required: spec.fetch(:required, false),
        sort_order: index
      )
      link.save!
    end
  end
end
