# frozen_string_literal: true

class SdModelCatalog
  class Error < StandardError; end
  class Unavailable < Error; end

  def initialize(switch_client: SdCppSwitchClient.new)
    @switch_client = switch_client
  end

  def configured?
    @switch_client.configured?
  end

  def model_names
    return fallback_models unless configured?

    response = @switch_client.models
    names = extract_models(response)
    raise Unavailable, "switchd returned no models" if names.blank?

    names
  rescue SdCppSwitchClient::Error => e
    raise Unavailable, e.message
  end

  def current_model
    return unless configured?

    response = @switch_client.current
    extract_current_model(response)
  rescue SdCppSwitchClient::Error => e
    Rails.logger.warn("SdModelCatalog: #{e.message}")
    nil
  end

  def loras_for(model)
    Array(Rails.application.config.x.nyoy.sd_model_loras.fetch(model, []))
  end

  def default_lora_for(model)
    Rails.application.config.x.nyoy.sd_model_default_loras[model]
  end

  private

  def fallback_models
    Rails.application.config.x.nyoy.default_sd_models
  end

  def extract_models(response)
    if response["models"].is_a?(Array)
      names = response["models"].filter_map { |item| name_from_item(item) }
      return names.presence
    end

    parse_stdout_list(response["stdout"]) ||
      extract_names(response["data"]).presence
  end

  def extract_current_model(response)
    response["model"].presence ||
      parse_stdout_value(response["stdout"]) ||
      response.dig("data", "model")
  end

  def parse_stdout_list(stdout)
    return if stdout.blank?

    stdout.lines.map(&:strip).reject(&:empty?).presence
  end

  def parse_stdout_value(stdout)
    parse_stdout_list(stdout)&.first
  end

  def extract_names(items)
    Array(items).filter_map { |item| name_from_item(item) }.uniq
  end

  def name_from_item(item)
    case item
    when String then item
    when Hash then item["name"] || item["id"] || item["model"]
    end
  end
end
