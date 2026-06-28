# frozen_string_literal: true

class PromptSpecGenerator
  class Error < StandardError; end

  SYSTEM_PROMPT = <<~PROMPT.squish
    You generate Stable Diffusion prompt specifications for sd.cpp txt2img.
    Respond with a single JSON object only. No markdown, no explanation.
    Use only LoRA names, sampler names, and model names from the allowed lists in the user message.
    Prefer tags and phrases suitable for English Stable Diffusion prompts.
    Include quality tags when appropriate.
    Fixed negative tags are applied automatically at image generation from skill and preset settings.
    Put only additional situational negative tags in negative_prompt. Do not repeat generic quality,
    text, watermark, or seal tags that are already applied at runtime.
  PROMPT

  MAX_TOKENS = 4096

  def initialize(
    generation:,
    retriever: PromptKnowledgeRetriever.new,
    client: LlamaCppClient.new,
    allowed_lists: nil
  )
    @generation = generation
    @retriever = retriever
    @client = client
    @allowed_lists = allowed_lists || PromptAllowedLists.new(record: generation)
  end

  def call
    query = @generation.japanese_prompt.to_s.strip
    raise Error, "japanese prompt required" if query.blank?

    rag = PromptRagContext.new(record: @generation, retriever: @retriever, allowed_lists: @allowed_lists).call(query)
    response = @client.chat(
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: build_user_prompt(query, rag) }
      ],
      temperature: 0.2,
      max_tokens: MAX_TOKENS,
      response_format: response_format_for(rag[:allowed]),
      read_timeout: Rails.application.config.x.nyoy.llama_read_timeout
    )

    content = LlamaCppClient.message_text(response)
    raise Error, "empty response from llama" if content.blank?

    spec = PromptSpec.from_json(
      parse_json(content),
      source_chunk_ids: rag[:chunk_ids],
      raw_response: content
    )
    enrich_lora_paths!(spec, rag[:allowed][:lora_entries])
    spec.validate!(
      allowed_loras: rag[:allowed][:lora_names],
      allowed_samplers: rag[:allowed][:samplers],
      allowed_models: rag[:allowed][:models]
    )
    spec
  rescue PromptSpec::ValidationError, JSON::ParserError => e
    raise Error, e.message
  end

  private

  def response_format_for(allowed)
    return unless Rails.application.config.x.nyoy.llama_json_schema

    PromptSpecJsonSchema.build(
      allowed_loras: allowed[:lora_names],
      allowed_samplers: allowed[:samplers],
      allowed_models: allowed[:models]
    )
  end

  def build_user_prompt(query, rag)
    allowed = rag[:allowed]

    <<~PROMPT
      Japanese request:
      #{query}

      Retrieved knowledge chunks:
      #{rag[:chunk_section]}

      Prompt presets:
      #{rag[:preset_section]}

      LoRA dictionary:
      #{rag[:lora_section]}

      Allowed models: #{allowed[:models].join(", ")}
      Allowed samplers: #{allowed[:samplers].join(", ")}
      Allowed LoRA names: #{allowed[:lora_names].join(", ")}

      Current generation defaults:
      model=#{@generation.sd_model}, size=#{@generation.width}x#{@generation.height}, steps=#{@generation.steps}, cfg=#{@generation.cfg_scale}, sampler=#{@generation.sampler_name}

      Return JSON with keys:
      positive_prompt, negative_prompt (supplemental tags only; fixed negatives are applied at runtime),
      model_family, width, height, steps, cfg_scale, sampler, seed, loras (array of {name, weight}), notes_ja, source_chunk_ids
    PROMPT
  end

  def parse_json(content)
    json_text = normalize_json_text(content)
    raise Error, "no JSON object found" if json_text.blank?

    JSON.parse(json_text)
  end

  def normalize_json_text(content)
    LlamaJsonParser.normalize(content)
  end

  def enrich_lora_paths!(spec, lora_entries)
    by_name = lora_entries.index_by { |entry| entry["name"] }
    spec.loras.each do |entry|
      catalog_entry = by_name[entry["name"]]
      entry["path"] ||= catalog_entry&.dig("path")
    end
  end
end
