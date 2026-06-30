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

ActiveRecord::Schema[8.1].define(version: 2026_06_29_150000) do
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

  create_table "image_generations", force: :cascade do |t|
    t.string "aspect_ratio"
    t.float "cfg_scale", default: 7.0, null: false
    t.datetime "created_at", null: false
    t.integer "draft_batch_size", default: 4, null: false
    t.integer "draft_steps"
    t.boolean "enable_hires", default: true, null: false
    t.text "error_message"
    t.datetime "finished_at"
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
    t.integer "seed"
    t.integer "selected_draft_index"
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.integer "steps", default: 20, null: false
    t.string "style_id"
    t.datetime "updated_at", null: false
    t.boolean "vae_tiling", default: false, null: false
    t.integer "width", default: 512, null: false
    t.index ["aspect_ratio"], name: "index_image_generations_on_aspect_ratio"
    t.index ["refine_render_preset_id"], name: "index_image_generations_on_refine_render_preset_id"
    t.index ["render_preset_id"], name: "index_image_generations_on_render_preset_id"
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
    t.datetime "updated_at", null: false
    t.boolean "use_source_dimensions", default: true, null: false
    t.boolean "vae_tiling", default: true, null: false
    t.integer "width", default: 768, null: false
    t.index ["status"], name: "index_img2img_generations_on_status"
    t.index ["style_id"], name: "index_img2img_generations_on_style_id"
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
    t.datetime "updated_at", null: false
    t.integer "width", default: 512, null: false
    t.index ["style_id"], name: "index_memo_illustrations_on_style_id"
  end

  create_table "prompt_knowledge_chunks", force: :cascade do |t|
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.vector "embedding", limit: 1024
    t.string "kind", default: "style", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "style_ref"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["embedding"], name: "index_prompt_knowledge_chunks_on_embedding_hnsw", opclass: :vector_cosine_ops, using: :hnsw
    t.index ["kind"], name: "index_prompt_knowledge_chunks_on_kind"
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

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "image_generations", "render_presets"
  add_foreign_key "image_generations", "render_presets", column: "refine_render_preset_id"
  add_foreign_key "prompt_style_loras", "lora_profiles"
  add_foreign_key "prompt_style_loras", "prompt_styles"
  add_foreign_key "prompt_style_models", "prompt_styles"
  add_foreign_key "prompt_style_models", "sd_model_profiles"
end
