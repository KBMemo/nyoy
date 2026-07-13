# frozen_string_literal: true

module ChatTools
  class ListSamplingPresets < RubyLLM::Tool
    description "有効な LLM サンプリングプリセット一覧を返す。apply_sampling_preset の preset_key 指定に使う。"

    def name
      "list_sampling_presets"
    end

    def execute
      {
        presets: LlmSamplingPreset.enabled.ordered.map(&:as_api_json)
      }
    end
  end
end
