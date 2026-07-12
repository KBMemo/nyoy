# frozen_string_literal: true

class SdModelSwitcher
  class Error < StandardError; end

  def initialize(catalog: SdModelCatalog.new, client: SdCppSwitchClient.new)
    @catalog = catalog
    @client = client
  end

  def switch(model, lora: nil)
    return false unless @client.configured?

    switch_key = model.presence
    raise Error, "モデル切替キーが未設定です" if switch_key.blank?

    lora = lora.presence || @catalog.default_lora_for(switch_key)
    @client.switch(switch_key, lora: lora)
    true
  end
end
