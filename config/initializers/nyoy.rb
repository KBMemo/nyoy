# frozen_string_literal: true

Rails.application.config.x.nyoy = ActiveSupport::OrderedOptions.new
Rails.application.config.x.nyoy.tap do |config|
  config.llama_cpp_url = ENV.fetch("LLAMA_CPP_URL", "http://balvenie:10010")
  config.llama_model = ENV.fetch("LLAMA_MODEL", "gemma-4-12b-it-vision-mtp")
  config.gpt_oss_llama_cpp_url = ENV["GPT_OSS_LLAMA_CPP_URL"]
  config.gpt_oss_model = ENV.fetch("GPT_OSS_MODEL", "gpt-oss")
  config.vision_llama_cpp_url = ENV.fetch("VISION_LLAMA_CPP_URL", "http://balvenie:10021")
  config.vision_llama_model = ENV.fetch("VISION_LLAMA_MODEL", "qwen2.5-vl-3b")
  config.sd_cpp_url = ENV.fetch("SDCPP_SERVER_URL", "http://balvenie:11234")
  config.sd_cpp_switchd_url = ENV.fetch("SDCPP_SWITCHD_URL", "http://balvenie:11334")
  config.sd_cpp_switchd_token = ENV["SDCPP_SWITCHD_TOKEN"]
  config.embeddings_url = ENV.fetch("EMBEDDINGS_URL", "http://balvenie:10020")
  config.embeddings_model = ENV.fetch("EMBEDDINGS_MODEL", "groonga/bge-m3-Q4_K_M-GGUF")
  config.embedding_dimensions = ENV.fetch("EMBEDDING_DIMENSIONS", 1024).to_i
  config.embedding_max_chars = ENV.fetch("EMBEDDING_MAX_CHARS", 1000).to_i
  config.llama_json_schema = ENV.fetch("LLAMA_JSON_SCHEMA", "true") == "true"
  config.llama_read_timeout = ENV.fetch("LLAMA_READ_TIMEOUT", 300).to_i
  config.default_sd_models = ENV.fetch(
    "SDCPP_DEFAULT_MODELS",
    "flat2d,anythingv5,dreamshaper8,pony-v6,illustrious_pencil-XL"
  ).split(",").map(&:strip).reject(&:empty?)
  config.sd_model_loras = {
    "illustrious_pencil-XL" => ["ChojuGiga_Illustrious"]
  }
  config.sd_model_default_loras = {
    "illustrious_pencil-XL" => "ChojuGiga_Illustrious"
  }
end
