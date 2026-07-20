# frozen_string_literal: true

Rails.application.config.x.nyoy = ActiveSupport::OrderedOptions.new
Rails.application.config.x.nyoy.tap do |config|
  config.llama_cpp_url = ENV.fetch("LLAMA_CPP_URL", "http://balvenie:10010")
  config.llama_model = ENV.fetch("LLAMA_MODEL", "gemma-4-e4b-it-qat-ud-q4-k-xl")
  config.gpt_oss_llama_cpp_url = ENV["GPT_OSS_LLAMA_CPP_URL"]
  config.gpt_oss_model = ENV.fetch("GPT_OSS_MODEL", "gpt-oss")
  config.llama_switchd_url = ENV.fetch("LLAMA_SWITCHD_URL", "http://balvenie:11335")
  config.llama_switchd_token = ENV["LLAMA_SWITCHD_TOKEN"]
  config.vision_llama_cpp_url = ENV.fetch("VISION_LLAMA_CPP_URL", "http://balvenie:10021")
  config.vision_llama_model = ENV.fetch("VISION_LLAMA_MODEL", "qwen3vl-4b-instruct-q4-k-m")
  config.sd_cpp_url = ENV.fetch("SDCPP_SERVER_URL", "http://balvenie:11234")
  config.sd_cpp_switchd_url = ENV.fetch("SDCPP_SWITCHD_URL", "http://balvenie:11334")
  config.sd_cpp_switchd_token = ENV["SDCPP_SWITCHD_TOKEN"]
  config.embeddings_url = ENV.fetch("EMBEDDINGS_URL", "http://balvenie:10020")
  config.embeddings_model = ENV.fetch("EMBEDDINGS_MODEL", "lfm2.5-embedding-350m-q4-k-m")
  config.embedding_dimensions = ENV.fetch("EMBEDDING_DIMENSIONS", 1024).to_i
  config.embedding_max_chars = ENV.fetch("EMBEDDING_MAX_CHARS", 1000).to_i
  config.llama_json_schema = ENV.fetch("LLAMA_JSON_SCHEMA", "true") == "true"
  config.llama_read_timeout = ENV.fetch("LLAMA_READ_TIMEOUT", 300).to_i
  # 通常は GET /props の total_slots を使う。ここは props 取得失敗時のフォールバック（0 で無効）。
  config.llama_slot_count = ENV.fetch("LLAMA_SLOT_COUNT", "0").to_i
  # total_slots >= 2 のとき末尾から補助 LLM 用に予約し、通常 Chat の KV cache を保護する。
  config.llama_aux_slot_count = ENV.fetch("LLAMA_AUX_SLOT_COUNT", "1").to_i
  config.llama_cache_prompt = ENV.fetch("LLAMA_CACHE_PROMPT", "true") == "true"
  config.llama_server_availability_max_age = ENV.fetch("LLAMA_SERVER_AVAILABILITY_MAX_AGE", 7200).to_i
  config.default_sd_models = ENV.fetch(
    "SDCPP_DEFAULT_MODELS",
    "flat2d,anythingv5,dreamshaper8,pony-v6,illustrious_pencil-XL,krea2"
  ).split(",").map(&:strip).reject(&:empty?)
  config.kbmemo_url = ENV.fetch("KBMEMO_URL", "https://kbmemo.net")
  config.kbmemo_api_token = ENV["KBMEMO_API_TOKEN"]
  config.tsuzura_url = ENV.fetch("TSUZURA_URL", "http://localhost:3008")
  config.tsuzura_api_token = ENV["TSUZURA_API_TOKEN"]
  config.searfront_url = ENV.fetch("SEARFRONT_URL") do
    ENV.fetch("SEARXNG_URL", "http://bowmore:13000")
  end
  config.searfront_api_token = ENV["SEARFRONT_TOKEN"].presence || ENV["SEARXNG_API_TOKEN"]
  config.readability_url = ENV.fetch("READABILITY_URL", "http://bowmore:8030")
  config.chat_context_turns = ENV.fetch("CHAT_CONTEXT_TURNS", 10).to_i
  config.memo_rag_enabled = ENV.fetch("MEMO_RAG_ENABLED", "true") == "true"
  # RAG の使い方: "tool" = モデルが recall_memos ツールを必要時に呼ぶ（毎ターンの前処理なし）、
  # "inject" = 毎ターン関連メモ抜粋を自動注入（高リコール・前処理あり）。
  config.memo_rag_mode = ENV.fetch("MEMO_RAG_MODE", "tool")
  # メインLLM（通常 Chat）の tool calling 制限。
  # restricted/read_only: 読み取り系のみ、all: write 系も含める、none: 無効。
  # 明示 allowlist がある場合は mode より優先する（例: "recall_memos,web_search,fetch_url"）。
  config.main_llm_tool_mode = ENV.fetch("MAIN_LLM_TOOL_MODE", "restricted")
  config.main_llm_tool_allowlist = ENV.fetch("MAIN_LLM_TOOL_ALLOWLIST", "")
  config.memo_rag_top_k = ENV.fetch("MEMO_RAG_TOP_K", 5).to_i
  config.memo_rag_top_k_simple = ENV.fetch("MEMO_RAG_TOP_K_SIMPLE", 3).to_i
  config.memo_rag_top_k_normal = ENV.fetch("MEMO_RAG_TOP_K_NORMAL", 5).to_i
  config.memo_rag_top_k_complex = ENV.fetch("MEMO_RAG_TOP_K_COMPLEX", 10).to_i
  config.memo_rag_max_chars = ENV.fetch("MEMO_RAG_MAX_CHARS", 12_000).to_i
  config.memo_rag_chunk_max_output_chars = ENV.fetch("MEMO_RAG_CHUNK_MAX_OUTPUT_CHARS", 800).to_i
  config.memo_rag_llm_compress = ENV.fetch("MEMO_RAG_LLM_COMPRESS", "false") == "true"
  config.memo_chunk_max_chars = ENV.fetch("MEMO_CHUNK_MAX_CHARS", 1500).to_i
  config.memo_ingest_page_limit = ENV.fetch("MEMO_INGEST_PAGE_LIMIT", 100).to_i
  config.memo_rag_webhook_enabled = ENV.fetch("MEMO_RAG_WEBHOOK_ENABLED", "false") == "true"
  config.memo_rag_webhook_secret = ENV["MEMO_RAG_WEBHOOK_SECRET"]
  config.chat_summary_enabled = ENV.fetch("CHAT_SUMMARY_ENABLED", "true") == "true"
  config.chat_summary_max_chars = ENV.fetch("CHAT_SUMMARY_MAX_CHARS", 1200).to_i
  config.chat_summary_llm = ENV.fetch("CHAT_SUMMARY_LLM", "false") == "true"
  config.chat_summary_max_tokens = ENV.fetch("CHAT_SUMMARY_MAX_TOKENS", 300).to_i
  config.memo_rag_max_tokens = ENV.fetch("MEMO_RAG_MAX_TOKENS", 1500).to_i
  config.chat_response_token_reserve = ENV.fetch("CHAT_RESPONSE_TOKEN_RESERVE", 2000).to_i
  config.style_plan_connection_key = ENV.fetch("STYLE_PLAN_CONNECTION_KEY", "llama_cpp")
  # UI（設定 → 既定モデル）未設定時のフォールバック。DB の app_settings が優先される。
  config.default_chat_connection_key = ENV.fetch("DEFAULT_CHAT_CONNECTION_KEY", "llama_cpp")
  config.agent_graph_role_profiles = {
    "draft" => ENV["AGENT_GRAPH_DRAFT_PROFILE"],
    "evidence_evaluator" => ENV["AGENT_GRAPH_EVIDENCE_EVALUATOR_PROFILE"],
    "final_answer" => ENV["AGENT_GRAPH_FINAL_ANSWER_PROFILE"],
    "intent" => ENV["AGENT_GRAPH_INTENT_PROFILE"],
    "memo_writer" => ENV["AGENT_GRAPH_MEMO_WRITER_PROFILE"],
    "planner" => ENV["AGENT_GRAPH_PLANNER_PROFILE"],
    "vision" => ENV["AGENT_GRAPH_VISION_PROFILE"]
  }.compact
  config.openai_url = ENV.fetch("OPENAI_API_URL", "https://api.openai.com")
  config.openai_chat_model = ENV.fetch("OPENAI_CHAT_MODEL", "gpt-4o-mini")
  # OPENAI_API_KEY is also used as the local llama-server compatibility token.
  # Prefer a dedicated real OpenAI key and accept the legacy variable unless it is the local sentinel.
  legacy_openai_key = ENV["OPENAI_API_KEY"].to_s.strip.presence
  legacy_openai_key = nil if legacy_openai_key == "local"
  config.openai_api_key = ENV["OPENAI_CHAT_API_KEY"].to_s.strip.presence || legacy_openai_key
  config.mcp_api_token = ENV["MCP_API_TOKEN"]
  # Streamable HTTP の DNS rebinding 保護。リモート公開時は false（API キーで保護）。
  config.mcp_dns_rebinding_protection = ENV.fetch("MCP_DNS_REBINDING_PROTECTION", "false") == "true"
  config.sd_model_loras = {
    "illustrious_pencil-XL" => [ "ChojuGiga_Illustrious" ]
  }
  config.sd_model_default_loras = {
    "illustrious_pencil-XL" => "ChojuGiga_Illustrious"
  }
end
