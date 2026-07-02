# frozen_string_literal: true

class MemoKnowledgeRetriever
  KEYWORD_LIMIT = 10
  RRF_K = 60

  def initialize(
    client: EmbeddingClient.new,
    tsurezure_client: TsurezureClient.new,
    limit: nil,
    keyword_limit: KEYWORD_LIMIT
  )
    @client = client
    @tsurezure_client = tsurezure_client
    @limit = limit
    @keyword_limit = keyword_limit
  end

  def retrieve(query, keywords: nil)
    text = query.to_s.strip
    return PromptKnowledgeChunk.none if text.blank?
    return PromptKnowledgeChunk.none unless PromptKnowledgeChunk.from_memo.embedded.exists?

    analysis = MemoRagQueryAnalyzer.analyze(text)
    effective_limit = positive_limit(@limit || analysis.top_k, analysis.top_k)
    search_keywords = Array(keywords).presence || analysis.keywords

    vector_hits = vector_search(text, limit: effective_limit)
    keyword_hits = keyword_search(search_keywords, limit: effective_limit)
    rank_chunks(vector_hits, keyword_hits).first(effective_limit)
  rescue EmbeddingClient::Error
    PromptKnowledgeChunk.none
  end

  private

  def vector_search(text, limit:)
    vector = @client.embed(input: text)
    PromptKnowledgeChunk.from_memo.embedded
                        .nearest_neighbors(:embedding, vector, distance: "cosine")
                        .limit(limit * 2)
                        .to_a
  end

  def keyword_search(keywords, limit:)
    return [] unless @tsurezure_client.configured?

    uids = keywords.flat_map { |keyword| memo_uids_for(keyword) }.uniq
    return [] if uids.empty?

    PromptKnowledgeChunk.from_memo.embedded
                        .where("metadata->>'memo_uid' IN (?)", uids)
                        .order(:id)
                        .limit(limit * 2)
                        .to_a
  rescue TsurezureClient::Error
    []
  end

  def memo_uids_for(keyword)
    response = @tsurezure_client.list_memos(
      q: keyword,
      limit: @keyword_limit,
      fields: "uid,title"
    )
    response.fetch("memos", []).filter_map { |memo| memo["uid"].presence }
  end

  def rank_chunks(vector_hits, keyword_hits)
    scores = Hash.new(0.0)
    vector_hits.each_with_index { |chunk, index| scores[chunk.id] += rrf_score(index) }
    keyword_hits.each_with_index { |chunk, index| scores[chunk.id] += rrf_score(index) }

    chunks_by_id = (vector_hits + keyword_hits).index_by(&:id)
    scores.sort_by { |id, score| [-score, id] }
          .filter_map { |id, _score| chunks_by_id[id] }
  end

  def rrf_score(rank)
    1.0 / (RRF_K + rank + 1)
  end

  def positive_limit(value, fallback)
    parsed = value.to_i
    parsed.positive? ? parsed : fallback
  end
end
