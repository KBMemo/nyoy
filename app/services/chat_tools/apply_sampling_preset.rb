# frozen_string_literal: true

module ChatTools
  class ApplySamplingPreset < RubyLLM::Tool
    description "サンプリングプリセットをチャットの llm_params に反映する。ユーザーがサンプリング変更を求めたときだけ使う。"

    def initialize(chat: nil)
      @chat = chat
    end

    def name
      "apply_sampling_preset"
    end

    param :preset_key, desc: "LlmSamplingPreset の key（list_sampling_presets 参照）", required: true
    param :chat_id, desc: "対象チャット id。Chat UI では省略可。MCP では必須", required: false

    def execute(preset_key:, chat_id: nil)
      chat = resolve_chat(chat_id)
      if chat.nil?
        return { error: "chat_id が必要です（MCP から呼ぶ場合は必須）" } if chat_id.blank?

        return { error: "チャットが見つかりません: #{chat_id}" }
      end

      preset = LlmSamplingPreset.enabled.find_by(key: preset_key.to_s)
      return { error: "プリセットが見つかりません: #{preset_key}" } if preset.nil?

      llm_params = ChatLlmSettings.normalize(preset.sampling_params.to_h)
      chat.update!(llm_params: llm_params)

      {
        chat_id: chat.id,
        preset_key: preset.key,
        llm_params: llm_params
      }
    end

    private

    def resolve_chat(chat_id)
      return @chat if @chat.present?
      return nil if chat_id.blank?

      Chat.find_by(id: chat_id)
    end
  end
end
