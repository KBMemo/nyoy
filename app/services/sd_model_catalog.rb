# frozen_string_literal: true

class SdModelCatalog
  def initialize(switch_client: SdCppSwitchClient.new)
    @switch_client = switch_client
  end

  def model_names
    if @switch_client.configured?
      response = @switch_client.models
      parse_stdout_list(response["stdout"]) ||
        extract_names(response["models"] || response["data"])
    else
      default_models
    end
  rescue SdCppSwitchClient::Error => e
    Rails.logger.warn("SdModelCatalog: #{e.message}")
    default_models
  end

  def current_model
    return unless @switch_client.configured?

    response = @switch_client.current
    parse_stdout_value(response["stdout"]) ||
      response["model"] ||
      response.dig("data", "model")
  rescue SdCppSwitchClient::Error => e
    Rails.logger.warn("SdModelCatalog: #{e.message}")
    nil
  end

  private

  def default_models
    Rails.application.config.x.nyoy.default_sd_models
  end

  def parse_stdout_list(stdout)
    return if stdout.blank?

    stdout.lines.map(&:strip).reject(&:empty?).presence
  end

  def parse_stdout_value(stdout)
    parse_stdout_list(stdout)&.first
  end

  def extract_names(items)
    Array(items).filter_map do |item|
      case item
      when String then item
      when Hash then item["name"] || item["id"] || item["model"]
      end
    end.uniq
  end
end
