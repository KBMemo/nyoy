# frozen_string_literal: true

module ServiceConnectionSeeds
  module_function

  def seed!
    definitions.each_with_index do |definition, index|
      record = ServiceConnection.find_or_initialize_by(key: definition.fetch(:key))
      attributes = {
        name: definition.fetch(:name),
        base_url: definition.fetch(:base_url),
        server_model: definition[:server_model],
        enabled: definition.fetch(:enabled, true),
        sort_order: definition.fetch(:sort_order, index),
        notes: definition[:notes]
      }
      attributes[:api_token] = definition[:api_token] if definition[:api_token].present?
      record.assign_attributes(attributes)
      record.save!
    end

    NyoyConnectionStore.clear_cache!
  end

  def definitions
    config = Rails.application.config.x.nyoy

    [
      {
        key: "llama_cpp",
        name: "Gemma Vision",
        base_url: config.llama_cpp_url,
        server_model: config.llama_model,
        notes: "スタイル計画・プロンプト翻訳などのテキスト LLM"
      },
      {
        key: "gpt_oss",
        name: "GPT-OSS",
        base_url: config.gpt_oss_llama_cpp_url.presence || config.llama_cpp_url,
        server_model: config.gpt_oss_model,
        notes: "チャット画面の GPT-OSS 用"
      },
      {
        key: "vision_llama",
        name: "Qwen2.5-VL",
        base_url: config.vision_llama_cpp_url,
        server_model: config.vision_llama_model,
        notes: "画像理解ページ"
      },
      {
        key: "embeddings",
        name: "bge-m3",
        base_url: config.embeddings_url,
        server_model: config.embeddings_model,
        notes: "ナレッジ chunk の埋め込み"
      },
      {
        key: "sd_cpp",
        name: "sd.cpp",
        base_url: config.sd_cpp_url,
        notes: "画像生成 API"
      },
      {
        key: "sd_switchd",
        name: "sd.cpp switchd",
        base_url: config.sd_cpp_switchd_url,
        api_token: config.sd_cpp_switchd_token,
        notes: "SD モデル切り替え"
      },
      {
        key: "kbmemo",
        name: "徒然（KBMemo）",
        base_url: config.kbmemo_url,
        api_token: config.kbmemo_api_token,
        enabled: config.kbmemo_api_token.present?,
        notes: "Chat メモツール用（clip API トークン）"
      },
      {
        key: "searxng",
        name: "SearXNG",
        base_url: config.searxng_url,
        api_token: config.searxng_api_token,
        enabled: config.searxng_url.present?,
        notes: "Chat web_search ツール用"
      }
    ]
  end
end
