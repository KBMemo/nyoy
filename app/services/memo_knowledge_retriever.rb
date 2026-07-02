# frozen_string_literal: true

class MemoKnowledgeRetriever
  DEFAULT_LIMIT = 5
  KEYWORD_LIMIT = 10
  RRF_K = 60

  def initialize(
    client: EmbeddingClient.new,
    tsurezure_client: TsurezureClient.new,
    limit: Rails.application.config.x.nyoy.memo_rag_top_k,
    keyword_limit: KEYWORD_LIMIT
  )
    @client = client
    @tsurezure_client = tsurezure_client
    @limit = positive_limit(limit, DEFAULT_LIMIT)
    @keyword_limit = keyword_limit
  end

  def retrieve(query)
    text = query.to_s.strip
    return PromptKnowledgeChunk.none if text.blank?
    return PromptKnowledgeChunk.none unless PromptKnowledgeChunk.from_memo.embedded.exists?

    vector_hits = vector_search(text)
    keyword_hits = keyword_search(text)
    rank_chunks(vector_hits, keyword_hits).first(@limit)
  rescue EmbeddingClient::Error
    PromptKnowledgeChunk.none
  end

  private

  def vector_search(text)
    vector = @client.embed(input: text)
    PromptKnowledgeChunk.from_memo.embedded
                        .nearest_neighbors(:embedding, vector, distance: "cosine")
                        .limit(@limit * 2)
                        .to_a
  end

  def keyword_search(text)
    return [] unless @tsurezure_client.configured?

    response = @tsurezure_client.list_memos(
      q: text,
      limit: @keyword_limit,
      fields: "uid,title"
    )
    uids = response.fetch("memos", []).filter_map { |memo| memo["uid"].presence }
    return [] if uids.empty?

    PromptKnowledgeChunk.from_memo.embedded
                        .where("metadata->>'memo_uid' IN (?)", uids)
                        .order(:id)
                        .limit(@limit * 2)
                        .to_a
  rescue TsurezureClient::Error
    []
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
