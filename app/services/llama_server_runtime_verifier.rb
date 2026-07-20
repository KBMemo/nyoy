# frozen_string_literal: true

class LlamaServerRuntimeVerifier
  class Error < StandardError; end

  def initialize(connection, probe: nil)
    @probe = probe || LlamaServerRuntimeProbe.new(
      control_url: connection.base_url,
      public_host: connection.llama_switchd_settings.public_host
    )
  end

  def call(detail)
    server = detail.fetch("server")
    result = @probe.call([ server ])[server.fetch("id")]
    raise Error, "起動後のRuntime情報を取得できません" unless result
    raise Error, "起動後のRuntime情報を取得できません: #{result.error}" if result.error.present?

    expected_alias = server.fetch("alias").to_s
    if result.model_alias.to_s != expected_alias
      raise Error, "起動後のRuntime Aliasが不一致です（switchd=#{expected_alias} / runtime=#{result.model_alias}）"
    end
    raise Error, "起動後のslot数を確認できません" unless result.total_slots.to_i.positive?

    expected_slots = positive_integer(detail.dig("values", "SLOTS"))
    if expected_slots && result.total_slots != expected_slots
      raise Error, "起動後のslot数が不一致です（definition=#{expected_slots} / runtime=#{result.total_slots}）"
    end

    {
      "model_alias" => result.model_alias,
      "total_slots" => result.total_slots
    }
  rescue KeyError => e
    raise Error, "起動後のRuntime検証に必要な情報がありません: #{e.message}"
  end

  private

  def positive_integer(value)
    number = Integer(value)
    number.positive? ? number : nil
  rescue ArgumentError, TypeError
    nil
  end
end
