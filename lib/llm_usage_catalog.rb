# frozen_string_literal: true

module LlmUsageCatalog
  Definition = Data.define(:key, :label, :capabilities)

  CAPABILITIES = %i[text_generation tool_calling vision embedding].freeze

  DEFINITIONS = [
    [ "chat.default", "通常Chat", %i[text_generation tool_calling] ],
    [ "agent.intent", "AgentGraph intent判定", %i[text_generation] ],
    [ "agent.planner", "AgentGraph調査計画", %i[text_generation] ],
    [ "agent.evidence_evaluator", "AgentGraph根拠評価", %i[text_generation] ],
    [ "agent.draft", "AgentGraphドラフト", %i[text_generation] ],
    [ "agent.final_answer", "AgentGraph最終回答", %i[text_generation] ],
    [ "vision.image_understanding", "画像理解", %i[text_generation vision] ],
    [ "embedding.memo_knowledge", "メモRAG埋め込み", %i[embedding] ],
    [ "embedding.prompt_knowledge", "プロンプトRAG埋め込み", %i[embedding] ],
    [ "image.style_plan", "画像生成style plan", %i[text_generation] ],
    [ "image.direct_prompt", "画像生成direct prompt", %i[text_generation] ],
    [ "utility.chat_history_summary", "Chat履歴要約", %i[text_generation] ],
    [ "utility.memo_chunk_compression", "メモchunk圧縮", %i[text_generation] ],
    [ "utility.sd_prompt_translation", "画像プロンプト翻訳", %i[text_generation] ]
  ].map do |key, label, capabilities|
    Definition.new(key:, label:, capabilities: capabilities.freeze)
  end.freeze

  INDEX = DEFINITIONS.index_by(&:key).freeze

  module_function

  def all
    DEFINITIONS
  end

  def keys
    INDEX.keys
  end

  def fetch(key)
    INDEX.fetch(key.to_s)
  end

  def required_capabilities(key)
    fetch(key).capabilities
  end

  def supporting(capability)
    normalized = capability.to_sym
    raise ArgumentError, "unknown LLM capability: #{capability}" unless CAPABILITIES.include?(normalized)

    DEFINITIONS.select { |definition| definition.capabilities.include?(normalized) }
  end
end
