# frozen_string_literal: true

class MemoRagQueryAnalyzer
  COMPLEX_PATTERN = /比較|違い|調査|まとめ|一覧|すべて|全部|関連|探索|教えて|説明して/i
  SIMPLE_MAX_CHARS = 40

  STOP_WORDS = %w[
    the a an and or but in on at to for of is are was were be been being
    this that these those with from as by it its
    の に は を が で と も か など する した して です ます ある いる なる れる
    什么 什么 请 我 你 他 她 它 的 了 吗 呢 吧
  ].freeze

  Analysis = Data.define(:complexity, :top_k, :keywords)

  def self.analyze(query)
    new.analyze(query)
  end

  def analyze(query)
    text = query.to_s.strip
    complexity = complexity_for(text)
    Analysis.new(
      complexity: complexity,
      top_k: top_k_for(complexity),
      keywords: keywords_for(text)
    )
  end

  def complexity_for(text)
    return :complex if text.length > 120 || text.match?(COMPLEX_PATTERN)
    return :simple if text.length <= SIMPLE_MAX_CHARS && !text.match?(/[?？]/)

    :normal
  end

  def top_k_for(complexity)
    config = Rails.application.config.x.nyoy
    case complexity
    when :simple then positive_int(config.memo_rag_top_k_simple, 3)
    when :complex then positive_int(config.memo_rag_top_k_complex, 10)
    else positive_int(config.memo_rag_top_k_normal, 5)
    end
  end

  def keywords_for(text)
    tokens = text.scan(/[\p{L}\p{N}_-]+/)
                 .map(&:downcase)
                 .reject { |token| token.length < 2 || stop_word?(token) }
                 .uniq
    return tokens.first(5) if tokens.any?

    [text]
  end

  private

  def stop_word?(token)
    STOP_WORDS.include?(token) || STOP_WORDS.include?(token.downcase)
  end

  def positive_int(value, fallback)
    parsed = value.to_i
    parsed.positive? ? parsed : fallback
  end
end
