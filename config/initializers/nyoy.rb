# frozen_string_literal: true

Rails.application.config.x.nyoy = ActiveSupport::OrderedOptions.new
Rails.application.config.x.nyoy.tap do |config|
  config.llama_cpp_url = ENV.fetch("LLAMA_CPP_URL", "http://balvenie:10010")
  config.sd_cpp_url = ENV.fetch("SDCPP_SERVER_URL", "http://balvenie:11234")
  config.sd_cpp_switchd_url = ENV.fetch("SDCPP_SWITCHD_URL", "http://balvenie:11334")
  config.sd_cpp_switchd_token = ENV["SDCPP_SWITCHD_TOKEN"]
  config.llama_model = ENV.fetch("LLAMA_MODEL", "gemma-4-12b-it-vision-mtp")
  config.default_sd_models = ENV.fetch(
    "SDCPP_DEFAULT_MODELS",
    "flat2d,anythingv5,dreamshaper8,pony-v6"
  ).split(",").map(&:strip).reject(&:empty?)
  config.sd_model_loras = {
    "pony-v6" => ["ChojuGiga_Illustrious"]
  }
  config.sd_model_default_loras = {
    "pony-v6" => "ChojuGiga_Illustrious"
  }
end
