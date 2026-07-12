# frozen_string_literal: true

class SdSamplerResolver
  class Error < StandardError; end

  def self.for(sd_model_profile:)
    new(sd_model_profile:).resolve
  end

  def initialize(sd_model_profile:, switcher: SdModelSwitcher.new, catalog: SdSamplerCatalog.new)
    @profile = sd_model_profile
    @switcher = switcher
    @catalog = catalog
  end

  def resolve
    result = fetch_live_samplers
    samplers = result.fetch(:names)
    default = default_sampler_name(samplers)

    {
      samplers: samplers,
      default: default,
      source: result.fetch(:source)
    }
  end

  private

  def fetch_live_samplers
    if @switcher.switch(@profile.switch_key)
      names = normalize_names(@catalog.names)
      return { names: names, source: "live" } if names.any?
    end

    family_fallback
  rescue SdCppSwitchClient::Error, SdModelSwitcher::Error, SdSamplerCatalog::Error
    family_fallback
  end

  def family_fallback
    { names: @profile.family_sampler_names, source: "family" }
  end

  def default_sampler_name(samplers)
    preferred = @profile.default_sampler_name
    return preferred if samplers.include?(preferred)

    samplers.first
  end

  def normalize_names(names)
    names.map(&:to_s).map(&:strip).reject(&:blank?).uniq
  end
end
