# frozen_string_literal: true

class OpenaiChatModelSettings
  attr_reader :catalog, :enabled

  def self.from(settings)
    new(settings)
  end

  def self.normalize(attrs)
    new(attrs).to_settings_h
  end

  def self.merge_catalog(settings, model_ids)
    current = from(settings)
    incoming = normalize_list(model_ids)
    return current.to_settings_h if incoming.empty?

    catalog = (current.catalog + incoming).uniq.sort
    preserved_enabled = current.enabled & catalog
    newly_discovered = incoming - current.catalog
    enabled = (preserved_enabled + newly_discovered).uniq.sort

    new("chat_models_catalog" => catalog, "chat_models" => enabled).to_settings_h
  end

  def initialize(source = nil)
    hash = stringify(source)
    @catalog = self.class.normalize_list(hash["chat_models_catalog"].presence || hash["chat_models"])
    @enabled = self.class.normalize_list(hash["chat_models"]) & @catalog
  end

  def enabled?(model_id)
    @enabled.include?(model_id.to_s)
  end

  def grouped_catalog
    @catalog.group_by { |model_id| group_name(model_id) }.sort_by { |name, _| name }
  end

  def to_settings_h
    {
      "chat_models_catalog" => @catalog,
      "chat_models" => @enabled
    }
  end

  def self.normalize_list(value)
    Array(value).map(&:to_s).filter_map(&:presence).uniq.sort
  end

  private

  def stringify(hash)
    return {} if hash.blank?

    if hash.key?(:catalog) || hash.key?(:enabled) || hash.key?("catalog") || hash.key?("enabled")
      catalog = Array(hash[:catalog] || hash["catalog"])
      enabled = enabled_from_param(hash[:enabled] || hash["enabled"], catalog)
      return {
        "chat_models_catalog" => catalog,
        "chat_models" => enabled
      }
    end

    hash.to_h.stringify_keys
  end

  def enabled_from_param(value, catalog)
    value = value.to_unsafe_h if value.respond_to?(:to_unsafe_h)

    selected = case value
               when Hash
                 value.select { |_, checked| ActiveModel::Type::Boolean.new.cast(checked) }.keys
               when Array
                 value
               else
                 []
               end
    selected = self.class.normalize_list(selected) & catalog
    return selected if selected.any? || catalog.empty?

    []
  end

  def group_name(model_id)
    model_id.sub(/-\d{4}(-\d{2}-\d{2})?\z/, "")
  end
end
