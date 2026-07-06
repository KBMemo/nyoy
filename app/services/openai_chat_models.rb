# frozen_string_literal: true

module OpenaiChatModels
  CHAT_PREFIX = /\A(gpt-|chatgpt-|o\d)/i
  EXCLUDED = /(whisper|tts|dall-e|embedding|audio|realtime|transcribe|moderation|davinci|babbage|gpt-image)/i

  module_function

  def filter(model_ids)
    Array(model_ids)
      .map(&:to_s)
      .filter_map(&:presence)
      .select { |model_id| chat_model?(model_id) }
      .uniq
      .sort
  end

  def chat_model?(model_id)
    model_id.match?(CHAT_PREFIX) && !model_id.match?(EXCLUDED)
  end
end
