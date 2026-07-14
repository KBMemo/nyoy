# frozen_string_literal: true

# RubyLLM's OpenAI streaming does not expose finish_reason. llama.cpp sets
# finish_reason=length when generation hits max_tokens / n_predict (server log:
# "truncated = 1"). Capture it on chunks and in thread-local state so
# ChatResponseJob can warn and end the turn clearly.
Rails.application.config.to_prepare do
  openai = RubyLLM::Providers::OpenAI
  next if openai.private_method_defined?(:build_chunk_without_nyoy_finish_reason)

  openai.alias_method :build_chunk_without_nyoy_finish_reason, :build_chunk
  openai.define_method(:build_chunk) do |data|
    chunk = build_chunk_without_nyoy_finish_reason(data)
    reason = data.dig("choices", 0, "finish_reason")
    if reason.present? && reason.to_s != "null"
      Nyoy::FinishReasonCapture.record!(reason)
      chunk.define_singleton_method(:finish_reason) { reason.to_s }
    end
    chunk
  end
  openai.send(:private, :build_chunk, :build_chunk_without_nyoy_finish_reason)
end
