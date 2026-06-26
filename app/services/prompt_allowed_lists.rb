# frozen_string_literal: true

class PromptAllowedLists
  def initialize(generation:, lora_catalog: SdLoraCatalog.new, sampler_catalog: SdSamplerCatalog.new)
    @generation = generation
    @lora_catalog = lora_catalog
    @sampler_catalog = sampler_catalog
  end

  def call
    catalog_loras = load_catalog_loras
    dictionary_loras = load_dictionary_loras
    lora_entries = merge_lora_entries(catalog_loras, dictionary_loras)

    {
      lora_entries: lora_entries,
      lora_names: lora_entries.filter_map { |entry| entry["name"].presence }.uniq,
      samplers: load_samplers,
      models: load_models,
      prompt_presets: load_prompt_presets,
      lora_dictionary: dictionary_loras
    }
  end

  private

  def load_catalog_loras
    Array(@lora_catalog.list)
  rescue SdLoraCatalog::Error
    []
  end

  def load_dictionary_loras
    PromptLora.for_model(@generation.sd_model).ordered.to_a
  end

  def merge_lora_entries(catalog_loras, dictionary_loras)
    by_name = catalog_loras.index_by { |entry| entry["name"] }

    dictionary_loras.each do |record|
      by_name[record.name] = record.to_lora_entry.merge(by_name[record.name] || {})
    end

    by_name.values
  end

  def load_samplers
    @sampler_catalog.names
  rescue SdSamplerCatalog::Error
    %w[euler_a]
  end

  def load_models
    (Rails.application.config.x.nyoy.default_sd_models + [@generation.sd_model]).compact.uniq
  end

  def load_prompt_presets
    family = PromptPreset.model_family_for(@generation.sd_model)
    scope = family ? PromptPreset.for_model(@generation.sd_model) : PromptPreset.ordered
    scope.ordered.to_a
  end
end
