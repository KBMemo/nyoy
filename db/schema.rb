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

ActiveRecord::Schema[8.1].define(version: 2026_06_24_124222) do
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

  create_table "generation_presets", force: :cascade do |t|
    t.float "cfg_scale", default: 6.0, null: false
    t.datetime "created_at", null: false
    t.boolean "default", default: false, null: false
    t.integer "height", default: 768, null: false
    t.text "loras", default: "[]", null: false
    t.string "name", null: false
    t.integer "prompt_skill_id"
    t.string "sampler_name", default: "euler_a", null: false
    t.string "sd_model", null: false
    t.integer "steps", default: 22, null: false
    t.datetime "updated_at", null: false
    t.boolean "vae_tiling", default: true, null: false
    t.integer "width", default: 768, null: false
    t.index ["default"], name: "index_generation_presets_on_default"
    t.index ["prompt_skill_id"], name: "index_generation_presets_on_prompt_skill_id"
  end

  create_table "image_generations", force: :cascade do |t|
    t.float "cfg_scale", default: 7.0, null: false
    t.datetime "created_at", null: false
    t.text "error_message"
    t.datetime "finished_at"
    t.integer "generation_preset_id"
    t.integer "height", default: 512, null: false
    t.text "japanese_prompt", null: false
    t.text "loras", default: "[]", null: false
    t.text "negative_prompt"
    t.text "prompt"
    t.integer "prompt_skill_id"
    t.string "sampler_name", default: "euler_a", null: false
    t.string "sd_model", null: false
    t.integer "seed"
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.integer "steps", default: 20, null: false
    t.datetime "updated_at", null: false
    t.boolean "vae_tiling", default: false, null: false
    t.integer "width", default: 512, null: false
    t.index ["generation_preset_id"], name: "index_image_generations_on_generation_preset_id"
    t.index ["prompt_skill_id"], name: "index_image_generations_on_prompt_skill_id"
  end

  create_table "memo_illustrations", force: :cascade do |t|
    t.text "body", null: false
    t.float "cfg_scale", default: 7.0, null: false
    t.datetime "created_at", null: false
    t.text "error_message"
    t.datetime "finished_at"
    t.integer "height", default: 512, null: false
    t.text "llama_raw_response"
    t.text "negative_prompt"
    t.text "positive_prompt"
    t.integer "prompt_skill_id", null: false
    t.string "sd_model", null: false
    t.integer "seed"
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.integer "steps", default: 20, null: false
    t.datetime "updated_at", null: false
    t.integer "width", default: 512, null: false
    t.index ["prompt_skill_id"], name: "index_memo_illustrations_on_prompt_skill_id"
  end

  create_table "prompt_skills", force: :cascade do |t|
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.boolean "default", default: false, null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["default"], name: "index_prompt_skills_on_default"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "generation_presets", "prompt_skills"
  add_foreign_key "image_generations", "generation_presets"
  add_foreign_key "image_generations", "prompt_skills"
  add_foreign_key "memo_illustrations", "prompt_skills"
end
