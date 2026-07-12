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

  test "does not call switch with blank model" do
    client = FakeClient.new(configured: true, calls: [])
    switcher = SdModelSwitcher.new(client: client)

    error = assert_raises(SdModelSwitcher::Error) { switcher.switch(nil) }
    assert_equal "モデル切替キーが未設定です", error.message
    assert_empty client.calls
  end

  test "passes default lora when switching illustrious_pencil-XL" do
    client = FakeClient.new(configured: true, calls: [])
    switcher = SdModelSwitcher.new(client: client)

    assert switcher.switch("illustrious_pencil-XL")
    assert_equal [{ model: "illustrious_pencil-XL", lora: "ChojuGiga_Illustrious" }], client.calls
  end

  test "does not pass lora for models without default lora" do
    client = FakeClient.new(configured: true, calls: [])
    switcher = SdModelSwitcher.new(client: client)

    assert switcher.switch("flat2d")
    assert_equal [{ model: "flat2d", lora: nil }], client.calls
  end
end
