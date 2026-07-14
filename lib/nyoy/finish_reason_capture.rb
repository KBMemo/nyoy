# frozen_string_literal: true

module Nyoy
  # Thread-local capture of OpenAI-compatible finish_reason from streaming
  # chunks (see config/initializers/ruby_llm_openai_finish_reason.rb).
  module FinishReasonCapture
    THREAD_KEY = :nyoy_last_finish_reason

    module_function

    def reset!
      Thread.current[THREAD_KEY] = nil
    end

    def last
      Thread.current[THREAD_KEY]
    end

    def record!(reason)
      value = reason.to_s.presence
      return if value.blank? || value == "null"

      Thread.current[THREAD_KEY] = value
    end

    def length?
      last.to_s == "length"
    end
  end
end
