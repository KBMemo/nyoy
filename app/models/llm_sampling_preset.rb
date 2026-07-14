# frozen_string_literal: true

class LlmSamplingPreset < ApplicationRecord
  validates :key, :name, presence: true
  validates :key, uniqueness: true, format: { with: /\A[a-z0-9_]+\z/, message: "は小文字英数字と _ のみ" }
  validates :params, presence: true
  validate :params_must_be_hash

  scope :enabled, -> { where(enabled: true) }
  scope :ordered, -> { order(sort_order: :asc, name: :asc) }
  scope :builtin, -> { where(builtin: true) }

  def sampling_params
    LlmSamplingParams.from(params)
  end

  def enable_thinking
    return nil unless params.is_a?(Hash)

    value =
      if params.key?("enable_thinking")
        params["enable_thinking"]
      elsif params.key?(:enable_thinking)
        params[:enable_thinking]
      end

    case value
    when true, "true", "1", 1 then "true"
    when false, "false", "0", 0 then "false"
    when "unset" then "unset"
    end
  end

  def prompt_conversion_attrs
    sampling_params.to_h.merge(
      "enable_thinking" => enable_thinking
    ).compact
  end

  def as_api_json
    {
      "id" => id,
      "key" => key,
      "name" => name,
      "notes" => notes,
      "model_name_match" => model_name_match,
      "builtin" => builtin,
      "enabled" => enabled,
      "params" => sampling_params.to_h_compact.merge(
        enable_thinking.present? ? { "enable_thinking" => enable_thinking == "true" } : {}
      )
    }
  end

  def matches_model?(model_name)
    needle = model_name_match.to_s.strip
    return false if needle.blank?

    model_name.to_s.downcase.include?(needle.downcase)
  end

  private

  def params_must_be_hash
    return if params.is_a?(Hash)

    errors.add(:params, "はオブジェクトである必要があります")
  end
end
