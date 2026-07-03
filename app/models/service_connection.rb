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
    readability
  ].freeze

  CHAT_BUILTIN_KEYS = %w[llama_cpp gpt_oss].freeze
  CUSTOM_LLM_KEY_FORMAT = /\Allm_[a-z0-9_]+\z/

  KEY_LABELS = {
    "llama_cpp" => "llama-server（テキスト LLM）",
    "gpt_oss" => "llama-server（GPT-OSS）",
    "vision_llama" => "llama-server（画像理解）",
    "embeddings" => "埋め込み API",
    "sd_cpp" => "sd.cpp サーバー",
    "sd_switchd" => "sd.cpp switchd",
    "kbmemo" => "徒然（KBMemo API）",
    "searxng" => "SearXNG（Web 検索）",
    "readability" => "readability-js-server（本文抽出）"
  }.freeze

  validates :key, :name, :base_url, presence: true
  validates :key, uniqueness: true
  validates :key, format: { with: /\A[a-z][a-z0-9_]*\z/, message: "は小文字英数字と _ のみ使えます" }
  validate :key_must_be_allowed
  validates :base_url, format: { with: %r{\Ahttps?://}, message: "は http:// または https:// で始めてください" }
  validates :server_model, presence: true, if: :custom_llm?

  scope :enabled, -> { where(enabled: true) }
  scope :ordered, -> { order(sort_order: :asc, name: :asc) }
  scope :chat_backends, -> { where(key: chat_keys) }
  scope :custom_llms, -> { where("key LIKE ?", "llm_%") }

  before_destroy :prevent_builtin_destroy
  after_save :clear_connection_cache
  after_save :sync_chat_models, if: :chat_backend?

  def builtin?
    BUILTIN_KEYS.include?(key)
  end

  def custom_llm?
    key.to_s.match?(CUSTOM_LLM_KEY_FORMAT)
  end

  def key_label
    return "カスタム LLM（#{key}）" if custom_llm?

    KEY_LABELS.fetch(key, key)
  end

  def chat_backend?
    self.class.chat_keys.include?(key)
  end

  def self.chat_keys
    CHAT_BUILTIN_KEYS + custom_llms.pluck(:key)
  end

  def self.available_keys
    BUILTIN_KEYS - pluck(:key)
  end

  private

  def key_must_be_allowed
    return if key.blank?
    return if builtin?
    return if custom_llm?

    errors.add(:key, "は組み込み key か llm_ で始まるカスタム key にしてください")
  end

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
