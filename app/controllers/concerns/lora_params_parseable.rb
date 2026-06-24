# frozen_string_literal: true

module LoraParamsParseable
  extend ActiveSupport::Concern

  private

  def parse_loras_param(raw)
    case raw
    when String
      JSON.parse(raw.presence || "[]")
    when Array
      raw
    else
      []
    end
  rescue JSON::ParserError
    []
  end

  def assign_loras_from_param(record, raw)
    record.loras_array = parse_loras_param(raw)
  end
end
