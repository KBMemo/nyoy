# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_07_21_060000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "vector"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "agent_checkpoints", force: :cascade do |t|
    t.bigint "agent_run_id", null: false
    t.datetime "created_at", null: false
    t.string "node_name", null: false
    t.jsonb "state", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["agent_run_id", "created_at"], name: "index_agent_checkpoints_on_agent_run_id_and_created_at"
    t.index ["agent_run_id"], name: "index_agent_checkpoints_on_agent_run_id"
  end

  create_table "agent_node_runs", force: :cascade do |t|
    t.bigint "agent_run_id", null: false
    t.datetime "created_at", null: false
    t.text "error_message"
    t.datetime "finished_at"
    t.jsonb "input_snapshot", default: {}, null: false
    t.string "node_name", null: false
    t.jsonb "output_snapshot", default: {}, null: false
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_run_id", "node_name"], name: "index_agent_node_runs_on_agent_run_id_and_node_name"
    t.index ["agent_run_id"], name: "index_agent_node_runs_on_agent_run_id"
  end

  create_table "agent_runs", force: :cascade do |t|
    t.bigint "chat_id", null: false
    t.datetime "created_at", null: false
    t.string "current_node"
    t.text "error_message"
    t.datetime "finished_at"
    t.string "graph_name", default: "research", null: false
    t.datetime "started_at"
    t.jsonb "state", default: {}, null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["chat_id"], name: "index_agent_runs_on_chat_id"
    t.index ["graph_name"], name: "index_agent_runs_on_graph_name"
    t.index ["status"], name: "index_agent_runs_on_status"
  end

  create_table "app_settings", force: :cascade do |t|
    t.string "agent_graph_intent_model_id"
    t.jsonb "agent_graph_role_profiles", default: {}, null: false
    t.datetime "created_at", null: false
    t.string "default_chat_connection_key"
    t.string "default_llm_sampling_preset_key"
    t.string "default_style_plan_connection_key"
    t.string "evidence_evaluator_model_id"
    t.string "final_answer_model_id"
    t.datetime "memo_knowledge_last_ingested_at"
    t.string "research_draft_fallback", default: "main", null: false
    t.string "research_draft_model_id"
    t.string "research_planner_model_id"
    t.datetime "updated_at", null: false
  end

  create_table "chats", force: :cascade do |t|
    t.text "context_summary"
    t.bigint "context_summary_until_message_id"
    t.datetime "created_at", null: false
    t.jsonb "llm_params", default: {}, null: false
    t.bigint "model_id"
    t.string "response_state", default: "idle", null: false
    t.datetime "updated_at", null: false
    t.index ["context_summary_until_message_id"], name: "index_chats_on_context_summary_until_message_id"
    t.index ["model_id"], name: "index_chats_on_model_id"
    t.index ["response_state"], name: "index_chats_on_response_state"
  end

  create_table "image_generations", force: :cascade do |t|
    t.string "aspect_ratio"
    t.float "cfg_scale", default: 7.0, null: false
    t.datetime "created_at", null: false
    t.integer "draft_batch_size", default: 4, null: false
    t.integer "draft_steps"
    t.boolean "enable_hires", default: true, null: false
    t.text "error_message"
    t.datetime "finished_at"
    t.string "generation_flow", default: "draft", null: false
    t.integer "height", default: 512, null: false
    t.float "hires_denoising_strength", default: 0.35, null: false
    t.float "hires_scale", default: 1.5, null: false
    t.integer "hires_steps"
    t.string "hires_upscaler", default: "Latent", null: false
    t.datetime "image_finished_at"
    t.datetime "image_started_at"
    t.text "japanese_prompt"
    t.text "loras", default: "[]", null: false
    t.text "negative_prompt"
    t.text "prompt"
    t.datetime "prompt_finished_at"
    t.jsonb "prompt_spec"
    t.datetime "prompt_started_at"
    t.jsonb "rag_source_chunk_ids", default: [], null: false
    t.float "refine_denoising_strength", default: 0.4, null: false
    t.bigint "refine_render_preset_id"
    t.integer "refine_steps"
    t.bigint "render_preset_id"
    t.jsonb "resolved_loras", default: [], null: false
    t.text "resolved_negative_prompt"
    t.jsonb "resolved_params", default: {}, null: false
    t.string "sampler_name", default: "euler_a", null: false
    t.string "sd_model"
    t.bigint "sd_model_profile_id"
    t.bigint "sd_prompt_template_id"
    t.integer "seed"
    t.integer "selected_draft_index"
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.integer "steps", default: 20, null: false
    t.string "style_id"
    t.string "style_plan_connection_key"
    t.datetime "updated_at", null: false
    t.boolean "vae_tiling", default: false, null: false
    t.integer "width", default: 512, null: false
    t.index ["aspect_ratio"], name: "index_image_generations_on_aspect_ratio"
    t.index ["generation_flow"], name: "index_image_generations_on_generation_flow"
    t.index ["refine_render_preset_id"], name: "index_image_generations_on_refine_render_preset_id"
    t.index ["render_preset_id"], name: "index_image_generations_on_render_preset_id"
    t.index ["sd_model_profile_id"], name: "index_image_generations_on_sd_model_profile_id"
    t.index ["sd_prompt_template_id"], name: "index_image_generations_on_sd_prompt_template_id"
    t.index ["style_id"], name: "index_image_generations_on_style_id"
  end

  create_table "img2img_generations", force: :cascade do |t|
    t.string "aspect_ratio"
    t.float "cfg_scale", default: 6.0, null: false
    t.datetime "created_at", null: false
    t.float "denoising_strength", default: 0.55, null: false
    t.text "error_message"
    t.datetime "finished_at"
    t.string "generation_mode", default: "img2img", null: false
    t.integer "height", default: 768, null: false
    t.datetime "image_finished_at"
    t.datetime "image_started_at"
    t.text "japanese_prompt"
    t.text "loras", default: "[]", null: false
    t.text "negative_prompt"
    t.text "prompt"
    t.datetime "prompt_finished_at"
    t.datetime "prompt_started_at"
    t.jsonb "rag_source_chunk_ids", default: [], null: false
    t.jsonb "resolved_loras", default: [], null: false
    t.text "resolved_negative_prompt"
    t.jsonb "resolved_params", default: {}, null: false
    t.string "sampler_name", default: "euler_a", null: false
    t.string "sd_model"
    t.integer "seed"
    t.string "source_label"
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.integer "steps", default: 22, null: false
    t.string "style_id"
    t.string "style_plan_connection_key"
    t.datetime "updated_at", null: false
    t.boolean "use_source_dimensions", default: true, null: false
    t.boolean "vae_tiling", default: true, null: false
    t.integer "width", default: 768, null: false
    t.index ["status"], name: "index_img2img_generations_on_status"
    t.index ["style_id"], name: "index_img2img_generations_on_style_id"
  end

  create_table "llama_server_operations", force: :cascade do |t|
    t.string "action", null: false
    t.datetime "created_at", null: false
    t.text "error_message"
    t.datetime "finished_at"
    t.string "managed_server_id", null: false
    t.jsonb "request_payload", default: {}, null: false
    t.jsonb "response_snapshot", default: {}, null: false
    t.bigint "service_connection_id", null: false
    t.datetime "started_at"
    t.string "status", default: "queued", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_llama_server_operations_on_created_at"
    t.index ["service_connection_id", "managed_server_id"], name: "index_active_llama_server_operations", unique: true, where: "((status)::text = ANY ((ARRAY['queued'::character varying, 'running'::character varying])::text[]))"
    t.index ["service_connection_id"], name: "index_llama_server_operations_on_service_connection_id"
  end

  create_table "llama_server_reconciliations", force: :cascade do |t|
    t.datetime "checked_at", null: false
    t.datetime "created_at", null: false
    t.text "error_message"
    t.jsonb "findings", default: [], null: false
    t.jsonb "server_snapshot", default: [], null: false
    t.bigint "service_connection_id", null: false
    t.string "status", null: false
    t.datetime "updated_at", null: false
    t.index ["checked_at"], name: "index_llama_server_reconciliations_on_checked_at"
    t.index ["service_connection_id"], name: "index_llama_server_reconciliations_on_service_connection_id"
  end

  create_table "llm_sampling_presets", force: :cascade do |t|
    t.boolean "builtin", default: false, null: false
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false
    t.string "key", null: false
    t.string "model_name_match"
    t.string "name", null: false
    t.text "notes"
    t.jsonb "params", default: {}, null: false
    t.integer "sort_order", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_llm_sampling_presets_on_key", unique: true
  end

  create_table "llm_usage_assignments", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false
    t.bigint "fallback_model_id"
    t.bigint "llm_sampling_preset_id"
    t.bigint "model_id", null: false
    t.datetime "updated_at", null: false
    t.string "usage_key", null: false
    t.index ["fallback_model_id"], name: "index_llm_usage_assignments_on_fallback_model_id"
    t.index ["llm_sampling_preset_id"], name: "index_llm_usage_assignments_on_llm_sampling_preset_id"
    t.index ["model_id"], name: "index_llm_usage_assignments_on_model_id"
    t.index ["usage_key"], name: "index_llm_usage_assignments_on_usage_key", unique: true
  end

  create_table "lora_profiles", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.decimal "default_multiplier", precision: 4, scale: 2, default: "0.7", null: false
    t.boolean "enabled", default: true, null: false
    t.string "family"
    t.string "key", null: false
    t.decimal "max_multiplier", precision: 4, scale: 2, default: "1.5", null: false
    t.decimal "min_multiplier", precision: 4, scale: 2, default: "0.0", null: false
    t.string "name", null: false
    t.text "notes"
    t.string "path", null: false
    t.string "trigger_words", default: [], null: false, array: true
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_lora_profiles_on_key", unique: true
    t.index ["path"], name: "index_lora_profiles_on_path", unique: true
  end

  create_table "memo_illustrations", force: :cascade do |t|
    t.text "body", null: false
    t.float "cfg_scale", default: 7.0, null: false
    t.datetime "created_at", null: false
    t.text "error_message"
    t.datetime "finished_at"
    t.integer "height", default: 512, null: false
    t.datetime "image_finished_at"
    t.datetime "image_started_at"
    t.text "llama_raw_response"
    t.text "negative_prompt"
    t.text "positive_prompt"
    t.datetime "prompt_finished_at"
    t.datetime "prompt_started_at"
    t.jsonb "rag_source_chunk_ids", default: [], null: false
    t.jsonb "resolved_loras", default: [], null: false
    t.text "resolved_negative_prompt"
    t.jsonb "resolved_params", default: {}, null: false
    t.string "sd_model"
    t.integer "seed"
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.integer "steps", default: 20, null: false
    t.string "style_id"
    t.string "style_plan_connection_key"
    t.datetime "updated_at", null: false
    t.integer "width", default: 512, null: false
    t.index ["style_id"], name: "index_memo_illustrations_on_style_id"
  end

  create_table "memo_rag_webhook_events", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.text "error_message"
    t.string "event_id", null: false
    t.string "event_type", null: false
    t.bigint "memo_id"
    t.string "memo_uid", null: false
    t.datetime "memo_updated_at"
    t.datetime "occurred_at", null: false
    t.datetime "processed_at"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id"], name: "index_memo_rag_webhook_events_on_event_id", unique: true
    t.index ["memo_uid"], name: "index_memo_rag_webhook_events_on_memo_uid"
    t.index ["status", "created_at"], name: "index_memo_rag_webhook_events_on_status_and_created_at"
  end

  create_table "messages", force: :cascade do |t|
    t.integer "cache_creation_tokens"
    t.integer "cached_tokens"
    t.boolean "cancelled", default: false, null: false
    t.bigint "chat_id", null: false
    t.text "content"
    t.json "content_raw"
    t.integer "context_build_elapsed_ms"
    t.datetime "created_at", null: false
    t.integer "first_chunk_elapsed_ms"
    t.integer "input_tokens"
    t.boolean "llama_cache_prompt"
    t.integer "llama_cache_slot_count"
    t.integer "llama_cache_slot_id"
    t.bigint "model_id"
    t.integer "output_tokens"
    t.integer "response_elapsed_ms"
    t.string "role", null: false
    t.integer "thinking_elapsed_ms"
    t.text "thinking_signature"
    t.text "thinking_text"
    t.integer "thinking_tokens"
    t.bigint "tool_call_id"
    t.boolean "truncated", default: false, null: false
    t.datetime "updated_at", null: false
    t.index ["chat_id"], name: "index_messages_on_chat_id"
    t.index ["model_id"], name: "index_messages_on_model_id"
    t.index ["role"], name: "index_messages_on_role"
    t.index ["tool_call_id"], name: "index_messages_on_tool_call_id"
  end

  create_table "models", force: :cascade do |t|
    t.jsonb "capabilities", default: []
    t.integer "context_window"
    t.datetime "created_at", null: false
    t.string "family"
    t.date "knowledge_cutoff"
    t.integer "max_output_tokens"
    t.jsonb "metadata", default: {}
    t.jsonb "modalities", default: {}
    t.datetime "model_created_at"
    t.string "model_id", null: false
    t.string "name", null: false
    t.jsonb "pricing", default: {}
    t.string "provider", null: false
    t.datetime "updated_at", null: false
    t.index ["capabilities"], name: "index_models_on_capabilities", using: :gin
    t.index ["family"], name: "index_models_on_family"
    t.index ["modalities"], name: "index_models_on_modalities", using: :gin
    t.index ["provider", "model_id"], name: "index_models_on_provider_and_model_id", unique: true
    t.index ["provider"], name: "index_models_on_provider"
  end

  create_table "prompt_knowledge_chunks", force: :cascade do |t|
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.vector "embedding", limit: 1024
    t.string "external_id"
    t.string "kind", default: "style", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "source", default: "prompt", null: false
    t.string "style_ref"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["embedding"], name: "index_prompt_knowledge_chunks_on_embedding_hnsw", opclass: :vector_cosine_ops, using: :hnsw
    t.index ["external_id"], name: "index_prompt_knowledge_chunks_on_external_id", unique: true, where: "(external_id IS NOT NULL)"
    t.index ["kind"], name: "index_prompt_knowledge_chunks_on_kind"
    t.index ["source"], name: "index_prompt_knowledge_chunks_on_source"
    t.index ["style_ref"], name: "index_prompt_knowledge_chunks_on_style_ref"
  end

  create_table "prompt_style_loras", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "inject_trigger_words", default: true, null: false
    t.bigint "lora_profile_id", null: false
    t.decimal "multiplier", precision: 4, scale: 2, default: "0.7", null: false
    t.bigint "prompt_style_id", null: false
    t.boolean "required", default: false, null: false
    t.integer "sort_order", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["lora_profile_id"], name: "index_prompt_style_loras_on_lora_profile_id"
    t.index ["prompt_style_id", "lora_profile_id"], name: "index_prompt_style_loras_on_style_and_lora", unique: true
    t.index ["prompt_style_id"], name: "index_prompt_style_loras_on_prompt_style_id"
  end

  create_table "prompt_style_models", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "default", default: false, null: false
    t.jsonb "param_overrides", default: {}, null: false
    t.bigint "prompt_style_id", null: false
    t.bigint "sd_model_profile_id", null: false
    t.integer "sort_order", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["prompt_style_id", "sd_model_profile_id"], name: "index_prompt_style_models_on_style_and_model", unique: true
    t.index ["prompt_style_id"], name: "index_prompt_style_models_on_prompt_style_id"
    t.index ["sd_model_profile_id"], name: "index_prompt_style_models_on_sd_model_profile_id"
  end

  create_table "prompt_styles", force: :cascade do |t|
    t.jsonb "aliases", default: [], null: false
    t.jsonb "allowed_overrides", default: {}, null: false
    t.jsonb "aspect_presets", default: {}, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "enabled", default: true, null: false
    t.jsonb "generation_defaults", default: {}, null: false
    t.string "name", null: false
    t.text "negative_prompt", default: "", null: false
    t.text "prompt_prefix", null: false
    t.text "prompt_suffix"
    t.integer "sort_order", default: 0, null: false
    t.string "style_id", null: false
    t.datetime "updated_at", null: false
    t.index ["style_id"], name: "index_prompt_styles_on_style_id", unique: true
  end

  create_table "render_presets", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "default", default: false, null: false
    t.integer "draft_batch_size"
    t.integer "draft_steps"
    t.boolean "enable_hires", default: false, null: false
    t.decimal "hires_denoising_strength", precision: 4, scale: 3
    t.decimal "hires_scale", precision: 4, scale: 2
    t.integer "hires_steps"
    t.string "hires_upscaler"
    t.string "kind", null: false
    t.string "name", null: false
    t.decimal "refine_denoising_strength", precision: 4, scale: 3
    t.integer "refine_steps"
    t.datetime "updated_at", null: false
    t.index ["kind", "default"], name: "index_render_presets_on_kind_and_default"
    t.index ["kind"], name: "index_render_presets_on_kind"
  end

  create_table "sd_model_profiles", force: :cascade do |t|
    t.string "base_url"
    t.datetime "created_at", null: false
    t.jsonb "default_params", default: {}, null: false
    t.boolean "enabled", default: true, null: false
    t.string "family", null: false
    t.string "key", null: false
    t.string "name", null: false
    t.text "notes"
    t.integer "sort_order", default: 0, null: false
    t.string "switch_key", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_sd_model_profiles_on_key", unique: true
    t.index ["switch_key"], name: "index_sd_model_profiles_on_switch_key"
  end

  create_table "sd_prompt_templates", force: :cascade do |t|
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false
    t.string "family"
    t.string "name", null: false
    t.text "notes"
    t.bigint "sd_model_profile_id"
    t.integer "sort_order", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["enabled", "sort_order"], name: "index_sd_prompt_templates_on_enabled_and_sort_order"
    t.index ["family"], name: "index_sd_prompt_templates_on_family"
    t.index ["sd_model_profile_id"], name: "index_sd_prompt_templates_on_sd_model_profile_id"
  end

  create_table "service_connections", force: :cascade do |t|
    t.string "adapter", default: "generic", null: false
    t.string "api_token"
    t.string "base_url", null: false
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false
    t.string "key", null: false
    t.string "legacy_key"
    t.string "managed_server_id"
    t.bigint "manager_connection_id"
    t.string "name", null: false
    t.text "notes"
    t.string "server_model"
    t.jsonb "settings", default: {}, null: false
    t.integer "sort_order", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["adapter"], name: "index_service_connections_on_adapter"
    t.index ["enabled"], name: "index_service_connections_on_enabled"
    t.index ["key"], name: "index_service_connections_on_key", unique: true
    t.index ["legacy_key"], name: "index_service_connections_on_legacy_key", unique: true
    t.index ["manager_connection_id", "managed_server_id"], name: "index_service_connections_on_manager_and_server"
  end

  create_table "tool_calls", force: :cascade do |t|
    t.jsonb "arguments", default: {}
    t.datetime "created_at", null: false
    t.bigint "message_id", null: false
    t.string "name", null: false
    t.text "thought_signature"
    t.string "tool_call_id", null: false
    t.datetime "updated_at", null: false
    t.index ["message_id"], name: "index_tool_calls_on_message_id"
    t.index ["name"], name: "index_tool_calls_on_name"
    t.index ["tool_call_id"], name: "index_tool_calls_on_tool_call_id", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "agent_checkpoints", "agent_runs"
  add_foreign_key "agent_node_runs", "agent_runs"
  add_foreign_key "agent_runs", "chats"
  add_foreign_key "chats", "models"
  add_foreign_key "image_generations", "render_presets"
  add_foreign_key "image_generations", "render_presets", column: "refine_render_preset_id"
  add_foreign_key "image_generations", "sd_model_profiles"
  add_foreign_key "image_generations", "sd_prompt_templates"
  add_foreign_key "llama_server_operations", "service_connections"
  add_foreign_key "llama_server_reconciliations", "service_connections"
  add_foreign_key "llm_usage_assignments", "llm_sampling_presets", on_delete: :nullify
  add_foreign_key "llm_usage_assignments", "models"
  add_foreign_key "llm_usage_assignments", "models", column: "fallback_model_id"
  add_foreign_key "messages", "chats"
  add_foreign_key "messages", "models"
  add_foreign_key "messages", "tool_calls"
  add_foreign_key "prompt_style_loras", "lora_profiles"
  add_foreign_key "prompt_style_loras", "prompt_styles"
  add_foreign_key "prompt_style_models", "prompt_styles"
  add_foreign_key "prompt_style_models", "sd_model_profiles"
  add_foreign_key "sd_prompt_templates", "sd_model_profiles"
  add_foreign_key "service_connections", "service_connections", column: "manager_connection_id"
  add_foreign_key "tool_calls", "messages"
end
