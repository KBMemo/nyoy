# frozen_string_literal: true

# Phase 1 (capability layer) seeds: sd_model_profiles and lora_profiles.
# The model list previously lived only in SDCPP_DEFAULT_MODELS; it now becomes
# DB-backed here.
module CapabilitySeeds
  # Generation params are now derived from the model family
  # (SdModelProfile::FAMILY_DEFAULT_PARAMS). Only set default_params here for a
  # model that must deviate from its family baseline.
  MODELS = [
    { key: "flat2d", name: "Flat2D", family: "sd15" },
    { key: "anythingv5", name: "Anything V5", family: "sd15" },
    { key: "dreamshaper8", name: "DreamShaper 8", family: "sd15" },
    { key: "pony-v6", name: "Pony Diffusion V6 XL", family: "pony" },
    { key: "illustrious_pencil-XL", name: "Illustrious Pencil XL", family: "illustrious" }
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
      notes: "鳥獣戯画 LoRA。Illustrious 系向け（pony 系でも利用可）。"
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
        default_params: attrs[:default_params] || {},
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
