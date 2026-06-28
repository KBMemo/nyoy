# frozen_string_literal: true

# Asks the LLM for a minimal style plan (style_id + subject_prompt +
# negative_extra + aspect_ratio) given a Japanese request and RAG knowledge.
# The fixed "作法" lives in StylePlanPrompts; variable guidance comes from chunks.
class StylePlanGenerator
  class Error < StandardError; end

  MAX_TOKENS = 1024

  Plan = Struct.new(
    :style_id, :subject_prompt, :negative_extra, :aspect_ratio,
    :source_chunk_ids, :raw_response,
    keyword_init: true
  )

  def initialize(flow:, client: LlamaCppClient.new, retriever: PromptKnowledgeRetriever.new)
    @flow = flow
    @client = client
    @retriever = retriever
  end

  def call(query, forced_style_id: nil)
    text = query.to_s.strip
    raise Error, "query required" if text.blank?

    styles = available_styles(forced_style_id)
    raise Error, "no enabled styles" if styles.empty?

    chunks = @retriever.retrieve(text).to_a
    response = @client.chat(
      messages: [
        { role: "system", content: StylePlanPrompts.system_for(@flow) },
        { role: "user", content: user_prompt(text, styles, chunks) }
      ],
      temperature: 0.2,
      max_tokens: MAX_TOKENS,
      response_format: response_format(styles),
      read_timeout: Rails.application.config.x.nyoy.llama_read_timeout
    )

    content = LlamaCppClient.message_text(response)
    raise Error, "empty response from llama" if content.blank?

    build_plan(content, styles, chunks)
  end

  private

  def available_styles(forced_style_id)
    scope = PromptStyle.enabled.ordered
    forced_style_id.present? ? scope.where(style_id: forced_style_id) : scope
  end

  def response_format(styles)
    return unless Rails.application.config.x.nyoy.llama_json_schema

    StylePlanJsonSchema.build(style_ids: styles.map(&:style_id))
  end

  def user_prompt(query, styles, chunks)
    <<~PROMPT
      Japanese request:
      #{query}

      Available styles (choose one style_id):
      #{styles_section(styles)}

      Retrieved knowledge:
      #{chunk_section(chunks)}

      Return JSON with keys: style_id, subject_prompt, negative_extra, aspect_ratio.
    PROMPT
  end

  def styles_section(styles)
    styles.map do |style|
      aliases = Array(style.aliases).join(", ")
      line = "- #{style.style_id}: #{style.name}"
      line += " — #{style.description}" if style.description.present?
      line += " (aliases: #{aliases})" if aliases.present?
      line
    end.join("\n")
  end

  def chunk_section(chunks)
    return "(no knowledge chunks matched)" if chunks.empty?

    chunks.map(&:to_rag_context).join("\n\n---\n\n")
  end

  def build_plan(content, styles, chunks)
    json = parse_json(content)
    style_id = json["style_id"].to_s.strip
    subject = json["subject_prompt"].to_s.strip

    raise Error, "style_id missing from llama response" if style_id.blank?
    raise Error, "subject_prompt missing from llama response" if subject.blank?
    unless styles.any? { |style| style.style_id == style_id }
      raise Error, "unknown style_id from llama: #{style_id}"
    end

    Plan.new(
      style_id: style_id,
      subject_prompt: subject,
      negative_extra: json["negative_extra"].to_s.strip,
      aspect_ratio: json["aspect_ratio"].presence,
      source_chunk_ids: chunks.map(&:id),
      raw_response: content
    )
  end

  def parse_json(content)
    json_text = LlamaJsonParser.normalize(content)
    raise Error, "no JSON object found in llama response" if json_text.blank?

    JSON.parse(json_text)
  rescue JSON::ParserError => e
    raise Error, "invalid JSON from llama: #{e.message}"
  end
end
