# frozen_string_literal: true

# Phase 1 (capability layer) seeds: sd_model_profiles and lora_profiles.
# The model list previously lived only in SDCPP_DEFAULT_MODELS; it now becomes
# DB-backed here.
module CapabilitySeeds
  SD15_PARAMS = {
    "width" => 512, "height" => 512, "steps" => 20,
    "cfg_scale" => 7.0, "sampler_name" => "euler_a"
  }.freeze

  XL_PARAMS = {
    "width" => 768, "height" => 768, "steps" => 24,
    "cfg_scale" => 6.0, "sampler_name" => "euler_a"
  }.freeze

  MODELS = [
    { key: "flat2d", name: "Flat2D", family: "sd15", default_params: SD15_PARAMS },
    { key: "anythingv5", name: "Anything V5", family: "sd15", default_params: SD15_PARAMS },
    { key: "dreamshaper8", name: "DreamShaper 8", family: "sd15", default_params: SD15_PARAMS },
    { key: "pony-v6", name: "Pony Diffusion V6 XL", family: "pony", default_params: XL_PARAMS },
    { key: "illustrious_pencil-XL", name: "Illustrious Pencil XL", family: "illustrious", default_params: XL_PARAMS }
  ].freeze

  LORAS = [
    {
      key: "chojugiga_illustrious",
      name: "ChojuGiga_Illustrious",
      family: "illustrious",
      path: "chojugiga/ChojuGiga_Illustrious.safetensors",
      trigger_words: %w[chojugiga emaki],
      default_multiplier: 0.8,
      min_multiplier: 0.7,
      max_multiplier: 0.9,
      notes: "鳥獣戯画 LoRA。Illustrious / pony 系向け。"
    }
  ].freeze

  module_function

  def seed!
    seed_models!
    seed_loras!
  end

  def seed_models!
    MODELS.each_with_index do |attrs, index|
      profile = SdModelProfile.find_or_initialize_by(key: attrs[:key])
      profile.assign_attributes(
        name: attrs[:name],
        family: attrs[:family],
        switch_key: attrs[:key],
        default_params: attrs[:default_params],
        sort_order: index,
        enabled: true
      )
      profile.save!
    end
  end

  def seed_loras!
    LORAS.each do |attrs|
      profile = LoraProfile.find_or_initialize_by(key: attrs[:key])
      profile.assign_attributes(attrs)
      profile.save!
    end
  end
end
