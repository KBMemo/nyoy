# frozen_string_literal: true

RubyLLM.configure do |config|
  config.openai_api_key = ENV.fetch("OPENAI_API_KEY", "local")
  config.openai_use_system_role = true
  config.request_timeout = Rails.application.config.x.nyoy.llama_read_timeout
  config.use_new_acts_as = true
end
