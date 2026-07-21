# frozen_string_literal: true

# Generates model-optimized SD prompt + negative_prompt JSON from Japanese input
# using SdPromptTemplate system guidance. Separate from SdPromptTranslator (inpaint).
class DirectPromptGenerator
  SYSTEM_PREFIX = <<~PROMPT.squish
    Generate English Stable Diffusion prompts from Japanese image descriptions.
    Output JSON only with keys prompt and negative_prompt.
    prompt is the positive txt2img prompt in English.
    negative_prompt is the negative txt2img prompt in English.
  PROMPT

  MAX_TOKENS = 2048

  class Error < StandardError; end

  def initialize(client: nil, connection_key: nil)
    @connection_key, @client = resolve_client(client, connection_key)
  end

  def self.build_system_prompt(template)
    parts = [ SYSTEM_PREFIX ]
    parts << template.body.to_s.strip if template&.body.present?
    parts.compact_blank.join("\n\n")
  end

  def generate(japanese_prompt, sd_model_profile:, sd_prompt_template: nil)
    text = japanese_prompt.to_s.strip
    raise Error, "japanese_prompt required" if text.blank?
    raise Error, "sd_model_profile required" if sd_model_profile.blank?

    template = SdPromptTemplateResolver.for(
      sd_model_profile: sd_model_profile,
      sd_prompt_template: sd_prompt_template
    )
    raise Error, "no enabled prompt template for model" if template.nil?

    settings = conversion_settings
    response = @client.chat(
      messages: [
        { role: "system", content: self.class.build_system_prompt(template) },
        { role: "user", content: user_prompt(text) }
      ],
      temperature: settings.resolved_temperature,
      max_tokens: settings.resolved_max_tokens(default: MAX_TOKENS),
      response_format: response_format,
      chat_template_kwargs: settings.chat_template_kwargs,
      sampling: settings.sampling,
      read_timeout: Rails.application.config.x.nyoy.llama_read_timeout
    )

    content = LlamaCppClient.message_text(response)
    raise Error, "empty response from llama" if content.blank?

    parse_result(content).merge(sd_prompt_template_id: template.id)
  end

  private

  def resolve_client(client, connection_key)
    key = connection_key.presence
    return [ key, client || StylePlanModelCatalog.client_for(connection_key: key) ] if key
    return [ StylePlanModelCatalog.default_connection_key, client ] if client

    resolution = LlmUsageResolver.resolve("image.direct_prompt")
    return [ resolution.connection.key, LlmUsageResolver.llama_client_for("image.direct_prompt") ] if resolution

    key = StylePlanModelCatalog.default_connection_key
    [ key, StylePlanModelCatalog.client_for(connection_key: key) ]
  end

  def user_prompt(japanese_prompt)
    return japanese_prompt if response_format.present?

    <<~PROMPT
      #{japanese_prompt}

      Return JSON with keys: prompt, negative_prompt.
    PROMPT
  end

  def response_format
    return unless StylePlanModelCatalog.json_schema_enabled?(@connection_key)

    DirectPromptJsonSchema.build
  end

  def conversion_settings
    @conversion_settings ||= StylePlanModelCatalog.prompt_conversion_settings(@connection_key)
  end

  def parse_result(content)
    json = parse_json(content)
    prompt = json["prompt"].to_s.strip
    negative_prompt = json["negative_prompt"].to_s.strip

    raise Error, "prompt missing from llama response" if prompt.blank?
    raise Error, "negative_prompt missing from llama response" if negative_prompt.blank?

    { prompt: prompt, negative_prompt: negative_prompt }
  end

  def parse_json(content)
    json_text = LlamaJsonParser.normalize(content)
    raise Error, "no JSON object found in llama response" if json_text.blank?

    LlamaJsonParser.repair_truncated(json_text)
  rescue LlamaJsonParser::Error => e
    raise Error, e.message
  end
end
