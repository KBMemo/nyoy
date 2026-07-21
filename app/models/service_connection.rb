# frozen_string_literal: true

class ServiceConnection < ApplicationRecord
  belongs_to :manager_connection, class_name: "ServiceConnection", optional: true
  has_many :managed_connections,
           class_name: "ServiceConnection",
           foreign_key: :manager_connection_id,
           dependent: :nullify,
           inverse_of: :manager_connection
  has_many :llama_server_operations, dependent: :destroy
  has_many :llama_server_reconciliations, dependent: :destroy
  has_many :models, dependent: :nullify
  BUILTIN_KEYS = %w[
    llama_cpp
    gpt_oss
    openai
    vision_llama
    embeddings
    sd_cpp
    sd_switchd
    llama_switchd
    kbmemo
    tsuzura
    searfront
    readability
  ].freeze

  ADAPTERS = %w[generic llama_cpp openai llama_switchd].freeze
  CUSTOM_LLM_KEY_FORMAT = /\Allm_[a-z0-9_]+\z/

  KEY_LABELS = {
    "llama_cpp" => "llama-server（テキスト LLM）",
    "gpt_oss" => "llama-server（GPT-OSS）",
    "openai" => "OpenAI（ChatGPT）",
    "vision_llama" => "llama-server（画像理解）",
    "embeddings" => "埋め込み API",
    "sd_cpp" => "sd.cpp サーバー",
    "sd_switchd" => "sd.cpp switchd",
    "llama_switchd" => "llama-switchd",
    "kbmemo" => "徒然（KBMemo API）",
    "tsuzura" => "葛籠（KBMemo Media API）",
    "searfront" => "searfront（Web 検索）",
    "readability" => "readability-js-server（本文抽出）"
  }.freeze

  validates :key, :name, :base_url, presence: true
  validates :adapter, inclusion: { in: ADAPTERS }
  validates :key, uniqueness: true
  validates :key, format: { with: /\A[a-z][a-z0-9_]*\z/, message: "は小文字英数字と _ のみ使えます" }
  validates :legacy_key, uniqueness: true, allow_nil: true
  validate :key_must_be_allowed
  validate :manager_must_be_llama_switchd
  validate :llama_switchd_settings_must_be_valid
  validates :base_url, format: { with: %r{\Ahttps?://}, message: "は http:// または https:// で始めてください" }
  validates :api_token, presence: true, if: -> { openai_chat_enabled? && !openai_environment_api_token? }
  validates :server_model, presence: true, if: :custom_llm?

  scope :enabled, -> { where(enabled: true) }
  scope :ordered, -> { order(sort_order: :asc, name: :asc) }
  scope :model_endpoints, -> { where(adapter: %w[llama_cpp openai]) }
  scope :custom_llms, -> { where("key LIKE ?", "llm_%") }

  before_validation :normalize_searfront_settings, if: :searfront?
  before_validation :normalize_custom_llm_adapter, if: :custom_llm?
  before_destroy :prevent_builtin_destroy
  after_save :clear_connection_cache
  after_save :sync_chat_models, if: :generative_model_endpoint?

  def builtin?
    BUILTIN_KEYS.include?(key) || BUILTIN_KEYS.include?(legacy_key)
  end

  def custom_llm?
    key.to_s.match?(CUSTOM_LLM_KEY_FORMAT)
  end

  def searfront?
    key.to_s == "searfront"
  end

  def openai?
    adapter == "openai"
  end

  def openai_chat_enabled?
    openai? && enabled?
  end

  def openai_environment_api_token?
    openai? && Rails.application.config.x.nyoy.openai_api_key.present?
  end

  def api_token_source
    return "database" if api_token.present?
    return "environment" if openai_environment_api_token?

    nil
  end

  def api_token_configured?
    api_token_source.present?
  end

  def searfront_settings
    SearfrontSettings.from(settings)
  end

  def openai_chat_model_settings
    OpenaiChatModelSettings.from(settings)
  end

  def prompt_conversion_settings
    PromptConversionSettings.from(settings)
  end

  def llama_switchd_settings
    LlamaSwitchdSettings.from(settings)
  end

  def assign_llama_switchd_settings(attrs)
    return unless key.to_s == "llama_switchd"

    self.settings = LlamaSwitchdSettings.merge_into(settings, attrs)
  end

  def assign_openai_chat_model_settings(attrs)
    return unless openai?

    merged = (settings || {}).merge(OpenaiChatModelSettings.normalize(attrs))
    self.settings = merged
  end

  def assign_searfront_settings(attrs)
    return unless searfront?

    # engines は searfront 側管理。UI からは受け付けず既存値を保持する。
    incoming = attrs.to_h.stringify_keys.except("engines")
    merged = (settings || {}).stringify_keys.merge(incoming)
    self.settings = SearfrontSettings.normalize(merged)
  end

  def assign_prompt_conversion_settings(attrs)
    return unless supports_prompt_conversion_settings?

    self.settings = PromptConversionSettings.merge_into(settings, attrs)
  end

  def supports_prompt_conversion_settings?
    generative_model_endpoint?
  end

  def key_label
    return "llama-server（#{key}）" if key.to_s.start_with?("llama_server_")
    return "カスタム LLM（#{key}）" if custom_llm?

    KEY_LABELS.fetch(key, key)
  end

  def model_endpoint?
    adapter.in?(%w[llama_cpp openai])
  end

  def generative_model_endpoint?
    return false unless model_endpoint?
    return true if openai?

    models_for_connection.any? { |model| LlmModelCapabilities.for(model).include?(:text_generation) } ||
      (server_model.present? && key != "embeddings")
  end

  def models_for_connection
    Model.where(service_connection_id: id).or(Model.where("metadata ->> 'connection_key' = ?", key.to_s))
  end

  def self.available_keys
    BUILTIN_KEYS - where(key: BUILTIN_KEYS).or(where(legacy_key: BUILTIN_KEYS)).pluck(Arel.sql("COALESCE(legacy_key, key)"))
  end

  def self.resolve(key)
    value = key.to_s
    find_by(key: value) || find_by(legacy_key: value)
  end

  def self.server_key_for(value)
    normalized = value.to_s.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, "")
    "llama_server_#{normalized}"
  end

  private

  def manager_must_be_llama_switchd
    return if manager_connection.nil? || manager_connection.key == "llama_switchd"

    errors.add(:manager_connection, "は llama_switchd 接続を指定してください")
  end

  def llama_switchd_settings_must_be_valid
    return unless key.to_s == "llama_switchd"
    return if llama_switchd_settings.valid?

    errors.add(:settings, "の公開ホストはportを含まないホスト名またはIPで指定してください")
  end

  def key_must_be_allowed
    return if key.blank?
    return if builtin?
    return if custom_llm?
    return if key.to_s.start_with?("llama_server_") && adapter == "llama_cpp"

    errors.add(:key, "は組み込み key か llm_ で始まるカスタム key にしてください")
  end

  def normalize_searfront_settings
    self.settings = SearfrontSettings.normalize(settings)
  end

  def normalize_custom_llm_adapter
    self.adapter = "llama_cpp" if adapter.blank? || adapter == "generic"
    return unless new_record? && server_model.present? && key.to_s.match?(CUSTOM_LLM_KEY_FORMAT)

    self.legacy_key ||= key
    self.key = self.class.server_key_for(managed_server_id.presence || server_model)
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
