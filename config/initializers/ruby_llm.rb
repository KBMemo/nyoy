# frozen_string_literal: true

RubyLLM.configure do |config|
  config.openai_api_key = ENV.fetch("OPENAI_API_KEY", "local")
  config.openai_use_system_role = true
  config.request_timeout = Rails.application.config.x.nyoy.llama_read_timeout
  config.use_new_acts_as = true
end

Rails.application.config.to_prepare do
  RubyLLM.configure do |config|
    llama_url = NyoyConnectionStore.url(:llama_cpp).to_s.sub(%r{/\z}, "")

    config.openai_api_base = "#{llama_url}/v1"
    config.default_model = NyoyConnectionStore.server_model(:llama_cpp)
  end
end
