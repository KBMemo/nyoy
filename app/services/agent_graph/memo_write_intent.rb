# frozen_string_literal: true

module AgentGraph
  # Decide whether a user turn should use MemoWrite Graph (create memo).
  # Prefer false negatives: ordinary chat keeps create_memo in the tool loop.
  #
  # Save-as-memo phrasing wins over Research only when the user is clearly
  # asking to persist existing content — not "調べてから保存" research framing.
  module MemoWriteIntent
    module_function

    NEGATIVE = [
      /\A\s*(こんにちは|こんばんは|おはよう|ありがとう|よろしく)/,
      /\A\s*(はい|ええ|うん|OK|ok|了解|わかった)\s*[。．!！?？]*\s*\z/i,
      /画像生成|イラスト生成|img2img|inpaint/i,
      /(描|画)いて\b/,
      /この画像(は|を|で|について)/
    ].freeze

    # Clear "save this as a memo" signals.
    STRONG = [
      /徒然に保存/,
      /徒然(メモ)?に書いて/,
      /徒然メモ(を)?(作|書|保存)/,
      /メモに保存/,
      /メモにして/,
      /メモを作/,
      /メモを書いて/,
      /メモとして保存/,
      /これを(徒然|メモ)/,
      /この(回答|内容|メッセージ|草案|ドラフト)を.*(保存|メモ|徒然)/,
      /create[_ ]?memo/i,
      /\bsave (this |it )?(as |to )?(a )?memo\b/i,
      /\bsave (this |it )?to tsurezure\b/i
    ].freeze

    RESEARCH_FRAMING = [
      /調べて/,
      /調査して/,
      /を調査/,
      /リサーチ/,
      /\bresearch\b/i,
      /出典/,
      /根拠/,
      /事実確認/
    ].freeze

    def match?(text)
      decision(text).fetch(:match)
    end

    def decision(text)
      raw = text.to_s
      normalized = raw.strip
      return reject("blank") if normalized.blank?
      return reject("negative", negative_hits(normalized)) if negative?(normalized)

      strong = strong_hits(normalized)
      return reject("no_signal") if strong.empty?

      if research_framed?(normalized) && !save_existing_content?(normalized)
        return reject("defer_research", strong)
      end

      accept("strong", strong)
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

    def research_framed?(text)
      RESEARCH_FRAMING.any? { |pattern| text.match?(pattern) }
    end

    def save_existing_content?(text)
      text.match?(/これを(徒然|メモ)|この(回答|内容|メッセージ|草案|ドラフト)を/)
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
