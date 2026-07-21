# frozen_string_literal: true

class MemoKnowledgeChunkCompressor
  CompressedChunk = Data.define(:title, :body, :metadata)

  def initialize(
    max_chars: Rails.application.config.x.nyoy.memo_rag_chunk_max_output_chars,
    llm_enabled: Rails.application.config.x.nyoy.memo_rag_llm_compress,
    client: nil
  )
    @max_chars = positive_int(max_chars, 800)
    @llm_enabled = llm_enabled
    @client = client || LlmUsageResolver.llama_client_for("utility.memo_chunk_compression")
  end

  def compress(chunks, query:)
    analysis = MemoRagQueryAnalyzer.analyze(query)

    chunks.map do |chunk|
      body = compress_body(chunk.body.to_s, keywords: analysis.keywords)
      body = llm_compress(body, query: query) if @llm_enabled && body.length > @max_chars

      CompressedChunk.new(
        title: chunk.title,
        body: body.byteslice(0, @max_chars),
        metadata: chunk.metadata
      )
    end
  end

  private

  def compress_body(body, keywords:)
    lines = body.lines.map(&:strip).reject(&:blank?)
    return body.squish if lines.length <= 3

    keyword_pattern = keywords.compact_blank.map { |word| Regexp.escape(word) }.join("|")
    if keyword_pattern.present?
      matched, = lines.partition { |line| line.match?(/#{keyword_pattern}/i) }
      selected = matched.presence || lines.first(4)
    else
      selected = lines.first(4)
    end

    selected.join("\n").squish
  end

  def llm_compress(body, query:)
    response = @client.chat(
      messages: [
        { role: "system", content: "与えられたメモ断片から、質問に関連する要点だけを短く残してください。" },
        { role: "user", content: "質問: #{query}\n\n断片:\n#{body}" }
      ],
      temperature: 0.1,
      max_tokens: 300
    )
    LlamaCppClient.message_text(response).presence || body
  rescue LlamaCppClient::Error
    body
  end

  def positive_int(value, fallback)
    parsed = value.to_i
    parsed.positive? ? parsed : fallback
  end
end
