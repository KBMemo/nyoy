# frozen_string_literal: true

class PromptSkillDraftGenerator
  class Error < StandardError; end

  OUTPUT_KINDS = {
    "json_plan" => "JSON 生成計画 (メモイラスト向け)",
    "translate" => "positive 翻訳のみ (画像生成フォールバック向け)"
  }.freeze

  SYSTEM_PROMPT = <<~PROMPT.squish
    You write PromptSkill system prompts for a Rails app that separates concerns:
    - PromptSkill body = LLM behavior only (role, output format, translation rules).
    - PromptKnowledgeChunk = variable style facts retrieved via RAG at generation time.
    - default_negative_prompt on the skill = execution-time fixed tags for sd.cpp (optional).

    Do NOT copy knowledge chunk tag lists or style dictionaries into the skill body.
    Instruct the LLM to rely on RAG-provided knowledge at runtime instead.
    For JSON plan skills, negative in JSON output must be supplemental only; fixed tags are applied at runtime.
    For translate skills, body must require positive-only comma-separated English output with no JSON and no parameters.
    Keep skill bodies concise and practical; avoid long duplicated examples.
    Write the skill body in English with clear markdown headings, matching existing Nyoy skill style.
  PROMPT

  JSON_PLAN_MAX_TOKENS = 4096
  TRANSLATE_MAX_TOKENS = 2048

  def initialize(client: LlamaCppClient.new)
    @client = client
  end

  def call(chunks:, output_kind: "json_plan")
    raise Error, "knowledge chunk required" if chunks.blank?
    raise Error, "unknown output kind" unless OUTPUT_KINDS.key?(output_kind)

    response = @client.chat(
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: build_user_prompt(chunks, output_kind) }
      ],
      temperature: 0.2,
      max_tokens: max_tokens_for(output_kind),
      response_format: response_format,
      read_timeout: read_timeout_for(output_kind)
    )

    content = LlamaCppClient.message_text(response)
    raise Error, "empty response from llama" if content.blank?

    parse_draft(content, chunks)
  rescue LlamaCppClient::Error => e
    raise Error, e.message
  end

  private

  def max_tokens_for(output_kind)
    output_kind == "translate" ? TRANSLATE_MAX_TOKENS : JSON_PLAN_MAX_TOKENS
  end

  def read_timeout_for(output_kind)
    output_kind == "translate" ? 180 : Rails.application.config.x.nyoy.llama_read_timeout
  end

  def response_format
    return unless Rails.application.config.x.nyoy.llama_json_schema

    PromptSkillDraftJsonSchema.build
  end

  def build_user_prompt(chunks, output_kind)
    knowledge = chunks.map(&:to_rag_context).join("\n\n---\n\n")
    kind_notes = if output_kind == "translate"
      <<~NOTES.strip
        Translate skill requirements:
        - Output ONLY comma-separated English positive prompts.
        - No JSON, markdown fences, negative prompts, or generation parameters in model output.
        - Keep the system prompt body compact (roughly 80 lines or less).
      NOTES
    else
      "JSON plan skill requirements: output valid JSON with positive, supplemental negative, width, height, steps, cfg_scale, seed."
    end

    <<~PROMPT
      Output kind: #{output_kind} (#{OUTPUT_KINDS[output_kind]})

      #{kind_notes}

      Source knowledge chunks (stay in RAG; do not paste verbatim into skill body):
      #{knowledge}

      Return JSON with keys:
      name (Japanese-friendly skill title),
      body (full system prompt for llama.cpp),
      default_negative_prompt (execution-time fixed tags inferred from knowledge, or empty string if none)
    PROMPT
  end

  def parse_draft(content, chunks)
    json_text = LlamaJsonParser.normalize(content)
    raise Error, "no JSON object found in llama response" if json_text.blank?

    json = JSON.parse(json_text)
    name = json["name"].to_s.strip
    body = json["body"].to_s.strip
    default_negative = json["default_negative_prompt"].to_s.strip

    raise Error, "name required" if name.blank?
    raise Error, "body required" if body.blank?

    {
      name: name,
      body: body,
      default_negative_prompt: default_negative,
      source_chunk_ids: chunks.map(&:id)
    }
  rescue JSON::ParserError => e
    raise Error, "invalid JSON from llama: #{e.message}"
  end
end
