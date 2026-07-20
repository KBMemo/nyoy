# frozen_string_literal: true

class LlamaServerDefinition
  include ActiveModel::Model
  include ActiveModel::Attributes

  INTEGER_FIELDS = {
    port: "PORT", ctx_size: "CTX_SIZE", slots: "SLOTS", batch_size: "BATCH_SIZE",
    ubatch_size: "UBATCH_SIZE", threads: "THREADS", threads_batch: "THREADS_BATCH",
    n_gpu_layers: "N_GPU_LAYERS", spec_draft_n_max: "SPEC_DRAFT_N_MAX"
  }.freeze
  STRING_FIELDS = {
    server_alias: "ALIAS", host: "HOST", device: "DEVICE", flash_attn: "FLASH_ATTN",
    mmproj: "MMPROJ", draft: "DRAFT", device_draft: "DEVICE_DRAFT", spec_type: "SPEC_TYPE"
  }.freeze
  BOOLEAN_FIELDS = { embedding: "EMBEDDING", jinja: "JINJA", mmproj_offload: "MMPROJ_OFFLOAD" }.freeze

  attribute :server_id, :string
  attribute :source_type, :string, default: "model"
  attribute :model, :string
  attribute :hf_repo, :string
  INTEGER_FIELDS.each_key { |name| attribute name, :integer }
  STRING_FIELDS.each_key { |name| attribute name, :string }
  BOOLEAN_FIELDS.each_key { |name| attribute name, :boolean }

  validates :server_id, presence: true, format: { with: /\A[a-z0-9][a-z0-9._-]{0,63}\z/ }
  validates :source_type, inclusion: { in: %w[model hf_repo] }
  validates :port, numericality: { only_integer: true, in: 1..65_535 }
  validates :ctx_size, :slots, :batch_size, :ubatch_size, :threads, :threads_batch, :spec_draft_n_max,
            allow_nil: true, numericality: { only_integer: true, greater_than: 0 }
  validate :source_must_be_present

  def self.from_api(server_id:, values:)
    reverse = INTEGER_FIELDS.merge(STRING_FIELDS).merge(BOOLEAN_FIELDS).invert
    attrs = values.each_with_object({ server_id: server_id }) do |(key, value), result|
      result[reverse[key]] = value if reverse[key]
    end
    if values["HF_REPO"].present?
      attrs[:source_type] = "hf_repo"
      attrs[:hf_repo] = values["HF_REPO"]
    else
      attrs[:source_type] = "model"
      attrs[:model] = values["MODEL"]
    end
    new(attrs)
  end

  def values
    result = {
      "MODEL" => source_type == "model" ? model.presence : nil,
      "HF_REPO" => source_type == "hf_repo" ? hf_repo.presence : nil
    }
    INTEGER_FIELDS.each { |attribute, key| result[key] = public_send(attribute) }
    STRING_FIELDS.each { |attribute, key| result[key] = public_send(attribute).presence }
    BOOLEAN_FIELDS.each { |attribute, key| result[key] = public_send(attribute) unless public_send(attribute).nil? }
    result
  end

  private

  def source_must_be_present
    value = source_type == "hf_repo" ? hf_repo : model
    errors.add(source_type == "hf_repo" ? :hf_repo : :model, "を入力してください") if value.blank?
  end
end
