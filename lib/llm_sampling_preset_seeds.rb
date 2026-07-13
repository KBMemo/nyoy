# frozen_string_literal: true

module LlmSamplingPresetSeeds
  module_function

  PRESETS = [
    {
      key: "qwen3_5_9b",
      name: "Qwen3.5 9B（コミュニティ推奨）",
      notes: "プロンプト変換・一般チャット向けのコミュニティ推奨サンプリング。enable_thinking はオフ。",
      model_name_match: "qwen3",
      builtin: true,
      sort_order: 10,
      enabled: true,
      params: {
        "temperature" => 0.7,
        "top_p" => 0.8,
        "top_k" => 20,
        "min_p" => 0.0,
        "presence_penalty" => 0.8,
        "frequency_penalty" => 0.2,
        "repeat_penalty" => 1.08,
        "max_tokens" => 1024,
        "enable_thinking" => false
      }
    }
  ].freeze

  def seed!
    PRESETS.each do |attrs|
      record = LlmSamplingPreset.find_or_initialize_by(key: attrs[:key])
      next if record.persisted? && !record.builtin?

      record.assign_attributes(attrs)
      record.save!
    end
  end
end
