# frozen_string_literal: true

class ServiceConnection < ApplicationRecord
  BUILTIN_KEYS = %w[
    llama_cpp
    gpt_oss
    vision_llama
    embeddings
    sd_cpp
    sd_switchd
    kbmemo
    searxng
  ].freeze

  KEY_LABELS = {
    "llama_cpp" => "llama-server（テキスト LLM）",
    "gpt_oss" => "llama-server（GPT-OSS）",
    "vision_llama" => "llama-server（画像理解）",
    "embeddings" => "埋め込み API",
    "sd_cpp" => "sd.cpp サーバー",
    "sd_switchd" => "sd.cpp switchd",
    "kbmemo" => "徒然（KBMemo API）",
    "searxng" => "SearXNG（Web 検索）"
  }.freeze

  CHAT_KEYS = %w[llama_cpp gpt_oss].freeze

  validates :key, :name, :base_url, presence: true
  validates :key, uniqueness: true
  validates :key, inclusion: { in: BUILTIN_KEYS }
  validates :base_url, format: { with: %r{\Ahttps?://}, message: "は http:// または https:// で始めてください" }

  scope :enabled, -> { where(enabled: true) }
  scope :ordered, -> { order(sort_order: :asc, name: :asc) }
  scope :chat_backends, -> { where(key: CHAT_KEYS) }

  before_destroy :prevent_builtin_destroy
  after_save :clear_connection_cache
  after_save :sync_chat_models, if: :chat_backend?

  def builtin?
    BUILTIN_KEYS.include?(key)
  end

  def key_label
    KEY_LABELS.fetch(key, key)
  end

  def chat_backend?
    CHAT_KEYS.include?(key)
  end

  def self.available_keys
    BUILTIN_KEYS - pluck(:key)
  end

  private

  def prevent_builtin_destroy
    return unless builtin?

    errors.add(:base, "組み込み接続は削除できません。無効化してください。")
    throw :abort
  end

  def clear_connection_cache
    NyoyConnectionStore.clear_cache!
    ChatTools::Registry.reset_client!
  end

  def sync_chat_models
    ChatModelCatalog.seed!
  end
end
