# frozen_string_literal: true

class SearxngSettings
  DEFAULTS = {
    "result_count" => 5,
    "concurrent_searches" => 1,
    "engines" => "duckduckgo,wikipedia",
    "retry_count" => 1
  }.freeze

  RANGES = {
    "result_count" => 1..10,
    "concurrent_searches" => 1..3,
    "retry_count" => 0..2
  }.freeze

  attr_reader :result_count, :concurrent_searches, :engines, :retry_count

  def self.load
    record = ServiceConnection.find_by(key: "searxng")
    from(record&.settings)
  end

  def self.from(hash)
    new(hash)
  end

  def self.normalize(hash)
    from(hash).to_h
  end

  def initialize(hash = nil)
    source = DEFAULTS.merge(stringify(hash))
    source["retry_count"] = source["retry"] if source["retry_count"].nil? && !source["retry"].nil?
    @result_count = clamp_int(source["result_count"], "result_count")
    @concurrent_searches = clamp_int(source["concurrent_searches"], "concurrent_searches")
    @engines = normalize_engines(source["engines"])
    @retry_count = clamp_int(source["retry_count"], "retry_count")
  end

  def engines_param
    engines
  end

  def to_h
    {
      "result_count" => result_count,
      "concurrent_searches" => concurrent_searches,
      "engines" => engines,
      "retry_count" => retry_count
    }
  end

  private

  def stringify(hash)
    return {} if hash.blank?

    hash.to_h.stringify_keys
  end

  def clamp_int(value, key)
    range = RANGES.fetch(key)
    number = Integer(value)
    number.clamp(range.begin, range.end)
  rescue ArgumentError, TypeError
    DEFAULTS.fetch(key)
  end

  def normalize_engines(value)
    list = value.to_s.split(",").map(&:strip).reject(&:blank?)
    list = DEFAULTS["engines"].split(",") if list.empty?
    list.join(",")
  end
end
