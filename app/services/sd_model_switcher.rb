# frozen_string_literal: true

class SdModelSwitcher
  def initialize(catalog: SdModelCatalog.new, client: SdCppSwitchClient.new)
    @catalog = catalog
    @client = client
  end

  def switch(model, lora: nil)
    return false unless @client.configured?

    lora = lora.presence || @catalog.default_lora_for(model)
    @client.switch(model, lora: lora)
    true
  end
end
