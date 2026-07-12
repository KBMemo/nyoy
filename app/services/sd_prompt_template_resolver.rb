# frozen_string_literal: true

class SdPromptTemplateResolver
  class Error < StandardError; end

  def self.for(sd_model_profile:, sd_prompt_template: nil)
    new(sd_model_profile:, sd_prompt_template:).resolve
  end

  def initialize(sd_model_profile:, sd_prompt_template: nil)
    @sd_model_profile = sd_model_profile
    @sd_prompt_template = sd_prompt_template
  end

  def resolve
    profile = resolve_profile
    return explicit_template if @sd_prompt_template.present?

    model_template(profile) || family_template(profile) || global_template
  end

  private

  def resolve_profile
    case @sd_model_profile
    when SdModelProfile
      @sd_model_profile
    when nil, ""
      raise Error, "sd_model_profile required"
    else
      SdModelProfile.find(@sd_model_profile)
    end
  end

  def explicit_template
    template = @sd_prompt_template
    template = SdPromptTemplate.find(template) unless template.is_a?(SdPromptTemplate)
    raise Error, "specified template is disabled" unless template.enabled?

    template
  end

  def model_template(profile)
    SdPromptTemplate.enabled.for_model(profile).ordered.first
  end

  def family_template(profile)
    SdPromptTemplate.enabled.for_family(profile.family).ordered.first
  end

  def global_template
    SdPromptTemplate.enabled.global.ordered.first
  end
end
