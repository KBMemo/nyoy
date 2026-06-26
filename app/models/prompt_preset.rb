# frozen_string_literal: true

class PromptPreset < ApplicationRecord
  MODEL_FAMILIES = %w[sdxl pony illustrious flux].freeze
  MODEL_FAMILY_LABELS = {
    "sdxl" => "SDXL",
    "pony" => "Pony",
    "illustrious" => "Illustrious",
    "flux" => "Flux"
  }.freeze

  COPY_SUFFIX_PATTERN = /[（(][0-9０-９]+[）)]\z/

  validates :name, :model_family, presence: true
  validates :name, uniqueness: true
  validates :model_family, inclusion: { in: MODEL_FAMILIES }

  scope :ordered, -> { order(model_family: :asc, name: :asc) }
  scope :for_model, ->(model) {
    family = model_family_for(model)
    family ? where(model_family: family) : none
  }

  def self.model_family_for(sd_model)
    case sd_model.to_s
    when /pony/i then "pony"
    when /illustrious/i then "illustrious"
    when /flux/i then "flux"
    when /sdxl|xl/i then "sdxl"
    end
  end

  def self.unique_copy_name(name)
    base = copy_name_base(name)
    candidate = name
    suffix = 1

    while exists?(name: candidate)
      candidate = "#{base}（#{full_width_number(suffix)}）"
      suffix += 1
    end

    candidate
  end

  def self.copy_name_base(name)
    name.to_s.sub(COPY_SUFFIX_PATTERN, "")
  end

  def self.full_width_number(number)
    number.to_s.tr("0-9", "０-９")
  end
  private_class_method :copy_name_base, :full_width_number

  def duplicate_with(attrs)
    PromptPreset.new(attrs.merge(name: self.class.unique_copy_name(attrs[:name].presence || name)))
  end

  def model_family_label
    MODEL_FAMILY_LABELS.fetch(model_family, model_family)
  end

  def default_params_json
    JSON.pretty_generate(default_params.presence || {})
  end

  def default_params_json=(value)
    self.default_params = value.to_s.strip.blank? ? {} : JSON.parse(value)
  rescue JSON::ParserError
    errors.add(:default_params, "must be valid JSON")
    @default_params_json_invalid = true
  end

  def to_rag_context
    lines = ["Preset: #{name} (#{model_family_label})"]
    lines << "positive template:\n#{positive_template}" if positive_template.present?
    lines << "negative template:\n#{negative_template}" if negative_template.present?
    lines << "default params: #{default_params.to_json}" if default_params.present?
    lines.join("\n\n")
  end
end
