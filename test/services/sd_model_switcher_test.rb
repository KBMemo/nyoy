# frozen_string_literal: true

require "test_helper"

class SdModelSwitcherTest < ActiveSupport::TestCase
  FakeClient = Struct.new(:configured, :calls, keyword_init: true) do
    def configured?
      configured
    end

    def switch(model, lora: nil)
      calls << { model: model, lora: lora }
    end
  end

  test "passes default lora when switching pony-v6" do
    client = FakeClient.new(configured: true, calls: [])
    switcher = SdModelSwitcher.new(client: client)

    assert switcher.switch("pony-v6")
    assert_equal [{ model: "pony-v6", lora: "ChojuGiga_Illustrious" }], client.calls
  end

  test "does not pass lora for models without default lora" do
    client = FakeClient.new(configured: true, calls: [])
    switcher = SdModelSwitcher.new(client: client)

    assert switcher.switch("flat2d")
    assert_equal [{ model: "flat2d", lora: nil }], client.calls
  end
end
