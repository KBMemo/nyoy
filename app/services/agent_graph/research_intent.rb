# frozen_string_literal: true

module AgentGraph
  # Keyword heuristic: decide whether a user turn should use Research Graph
  # instead of the default LLM tool loop. R0 keeps this simple and deterministic.
  module ResearchIntent
    module_function

    PATTERNS = [
      /調査/,
      /根拠/,
      /出典/,
      /どこから/,
      /なぜ.*来/,
      /元はどこ/,
      /裏付け/,
      /事実確認/,
      /リサーチ/,
      /\bresearch\b/i,
      /\bsources?\b/i,
      /\bcitations?\b/i
    ].freeze

    def match?(text)
      text.to_s.match?(Regexp.union(PATTERNS))
    end
  end
end
