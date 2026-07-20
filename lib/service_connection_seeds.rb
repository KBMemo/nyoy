# frozen_string_literal: true

module ServiceConnectionSeeds
  module_function

  def seed!
    upsert_definitions!(definitions)
    NyoyConnectionStore.clear_cache!
  end

  # bin/dev 起動時: env.development → DB。1件の検証失敗で全体を止めない。
  def sync_from_env!
    definitions.each_with_index { |definition, index| sync_definition(definition, index) }
    NyoyConnectionStore.clear_cache!
  end

  def seed_missing!
    missing = definitions.reject { |definition| ServiceConnection.exists?(key: definition.fetch(:key)) }
    upsert_definitions!(missing)
    missing.size
  end

  def upsert_definitions!(definitions)
    definitions.each_with_index do |definition, index|
      upsert_definition!(definition, index)
    end
  end

  def sync_definition(definition, index)
    record = ServiceConnection.find_or_initialize_by(key: definition.fetch(:key))
    record.assign_attributes(sync_attributes_for(definition, record, index))
    return if record.save

    warn "ServiceConnectionSeeds: #{definition.fetch(:key)} を env から同期できませんでした " \
         "(#{record.errors.full_messages.join(', ')})"
  end

  def upsert_definition!(definition, index)
    record = ServiceConnection.find_or_initialize_by(key: definition.fetch(:key))
    attributes = definition_attributes(definition, record, index)
    record.assign_attributes(attributes)
    record.save!
    record
  end

  # env → DB 同期用。既存レコードの enabled は UI / DB 設定を上書きしない。
  def sync_attributes_for(definition, record, index)
    attributes = {
      name: definition.fetch(:name),
      base_url: definition.fetch(:base_url),
      server_model: definition[:server_model],
      sort_order: definition.fetch(:sort_order, index),
      notes: definition[:notes]
    }
    attributes[:api_token] = definition[:api_token] if definition[:api_token].present?
    if definition[:settings].present? && (record.new_record? || record.settings.blank?)
      attributes[:settings] = definition[:settings]
    end
    attributes[:enabled] = definition.fetch(:enabled, true) if record.new_record?
    attributes
  end

  def definition_attributes(definition, record, index)
    attributes = {
      name: definition.fetch(:name),
      base_url: definition.fetch(:base_url),
      server_model: definition[:server_model],
      enabled: definition.fetch(:enabled, true),
      sort_order: definition.fetch(:sort_order, index),
      notes: definition[:notes]
    }
    attributes[:api_token] = definition[:api_token] if definition[:api_token].present?
    if definition[:settings].present? && (record.new_record? || record.settings.blank?)
      attributes[:settings] = definition[:settings]
    end
    attributes
  end

  def definitions
    config = Rails.application.config.x.nyoy
    openai_api_key = config.openai_api_key.to_s.strip.presence
    openai_api_key = nil if openai_api_key == "local"

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
        key: "openai",
        name: "OpenAI（ChatGPT）",
        base_url: config.openai_url,
        server_model: config.openai_chat_model,
        api_token: openai_api_key,
        enabled: openai_api_key.present?,
        notes: "OpenAI API（ChatGPT）。API キーを設定し「モデル取得」で利用可能モデルを同期してください。",
        settings: { "chat_models" => [] }
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
        key: "tsuzura",
        name: "葛籠（KBMemo Media）",
        base_url: config.tsuzura_url,
        api_token: config.tsuzura_api_token,
        enabled: config.tsuzura_api_token.present?,
        notes: "Chat 画像アーカイブ・メディア参照（tsuzura API トークン）"
      },
      {
        key: "searfront",
        name: "searfront",
        base_url: config.searfront_url,
        api_token: config.searfront_api_token,
        enabled: config.searfront_url.present?,
        notes: "Chat web_search 用（searfront `/v1/search`）",
        settings: SearfrontSettings::DEFAULTS
      },
      {
        key: "readability",
        name: "readability-js-server",
        base_url: config.readability_url,
        enabled: config.readability_url.present?,
        notes: "Chat fetch_url ツール用（Mozilla Readability）"
      }
    ]
  end
end
