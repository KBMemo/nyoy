# frozen_string_literal: true

module AgentGraph
  # Decide whether a user turn should use Research Graph instead of the
  # default LLM tool loop. Deterministic keyword scoring (no LLM).
  #
  # Prefer false negatives over false positives: ordinary chat can still use
  # tools, while accidental Graph entry skips the normal conversational loop.
  module ResearchIntent
    module_function

    # Clear non-research turns (checked first).
    NEGATIVE = [
      /\A\s*(こんにちは|こんばんは|おはよう|ありがとう|よろしく)/,
      /\A\s*(はい|ええ|うん|OK|ok|了解|わかった)\s*[。．!！?？]*\s*\z/i,
      /画像生成|イラスト生成|img2img|inpaint/i,
      /(描|画)いて\b/,
      /この画像(は|を|で|について)/,
      /写真(は|を|で)何/,
      /サンプリング|temperature|top_p/i
    ].freeze

    # Strong research framing — any one hit is enough.
    STRONG = [
      /調べて/,
      /調べよう/,
      /調査して/,
      /調査(を|の)?(お願い|してほしい|してくれ)/,
      /を調査/,
      /調査日/,
      /根拠/,
      /出典/,
      /裏付け/,
      /事実確認/,
      /どこから(来|出|取)/,
      /なぜ.*来(た|て)/,
      /元はどこ/,
      /リサーチ/,
      /情報を(集め|探して|収集)/,
      /最新(の)?(情報|ニュース|リリース|動向)/,
      /公式(サイト|情報|発表|文書)?(を)?(確認|調べ|見て)/,
      /\bresearch\b/i,
      /\blook(?:ing)?\s*up\b/i,
      /\bfact[- ]?check/i,
      /\bsources?\b/i,
      /\bcitations?\b/i,
      /\baccording to\b/i
    ].freeze

    # Weaker cues — need a partner cue (URL, search verb, or another weak hit).
    WEAK = [
      /確認して/,
      /確かめて/,
      /検索/,
      /ニュース/,
      /公式/,
      /リリース/,
      /規格/,
      /なにが根拠/,
      /何が根拠/,
      /\bfind out\b/i,
      /\bverify\b/i
    ].freeze

    URL = %r{https?://}i

    def match?(text)
      decision(text).fetch(:match)
    end

    def decision(text)
      raw = text.to_s
      normalized = raw.strip
      return reject("blank") if normalized.blank?
      return reject("negative", negative_hits(normalized)) if negative?(normalized)

      strong = strong_hits(normalized)
      return accept("strong", strong) if strong.any?

      weak = weak_hits(normalized)
      has_url = normalized.match?(URL)

      if has_url && (weak.any? || fetch_framed?(normalized))
        return accept("url+context", weak + (has_url ? [ "url" ] : []))
      end

      return accept("weak×2", weak) if weak.size >= 2

      reject("no_signal", weak)
    end

    def negative?(text)
      negative_hits(text).any?
    end

    def negative_hits(text)
      NEGATIVE.select { |pattern| text.match?(pattern) }.map { |pattern| pattern.source }
    end

    def strong_hits(text)
      STRONG.select { |pattern| text.match?(pattern) }.map { |pattern| pattern.source }
    end

    def weak_hits(text)
      WEAK.select { |pattern| text.match?(pattern) }.map { |pattern| pattern.source }
    end

    # URL alone is not enough ("見て" / "要約して" / "確認" framing helps).
    def fetch_framed?(text)
      text.match?(/この(ページ|URL|リンク)|ページを(見て|確認|要約|調べ)|URLを(見て|確認|要約|調べ)|要約して|内容(を|が)(教え|まとめ)/)
    end

    def accept(reason, hits)
      { match: true, reason: reason, hits: hits }
    end

    def reject(reason, hits = [])
      { match: false, reason: reason, hits: hits }
    end
    private_class_method :accept, :reject
  end
end
