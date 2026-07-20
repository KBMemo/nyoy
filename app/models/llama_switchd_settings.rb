# frozen_string_literal: true

class LlamaSwitchdSettings
  KEY = "llama_switchd"

  attr_reader :public_host

  def self.from(settings)
    values = settings.to_h.stringify_keys.fetch(KEY, {}).to_h.stringify_keys
    new(public_host: values["public_host"])
  end

  def self.merge_into(settings, attrs)
    existing = settings.to_h.deep_stringify_keys
    values = new(public_host: attrs.to_h.stringify_keys["public_host"])
    existing.merge(KEY => { "public_host" => values.public_host })
  end

  def initialize(public_host: nil)
    @public_host = public_host.to_s.strip.presence
  end

  def valid?
    return true if public_host.blank?

    uri = URI.parse("http://#{public_host}")
    uri.host.present? && public_host == uri.host && uri.userinfo.nil? && uri.path.empty? && uri.query.nil? && uri.fragment.nil?
  rescue URI::InvalidURIError
    false
  end
end
