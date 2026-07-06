# frozen_string_literal: true

require "test_helper"

class ChatResponseControlTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
    @chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
  end

  test "mark_running and finish reset response state" do
    ChatResponseControl.mark_running!(@chat)
    assert @chat.reload.responding?

    ChatResponseControl.finish!(@chat)
    assert_equal "idle", @chat.reload.response_state
  end

  test "cancel marks chat as cancelled" do
    ChatResponseControl.mark_running!(@chat)
    ChatResponseControl.cancel!(@chat)

    assert_equal "cancelled", @chat.reload.response_state
  end

  test "check raises when cancelled" do
    ChatResponseControl.mark_running!(@chat)
    ChatResponseControl.cancel!(@chat)

    assert_raises(ChatResponseControl::Cancelled) do
      ChatResponseControl.check!(@chat.id)
    end
  end

  test "responding reads current state from the database" do
    ChatResponseControl.mark_running!(@chat)
    assert ChatResponseControl.responding?(@chat.id)

    ChatResponseControl.finish!(@chat)
    refute ChatResponseControl.responding?(@chat.id)
  end

  test "install_checks callback accepts tool_call argument" do
    ChatResponseControl.mark_running!(@chat)
    llm_chat = @chat.to_llm
    tool_call = RubyLLM::ToolCall.new(id: "call_1", name: "fetch_url", arguments: { url: "https://example.com" })

    assert_nothing_raised do
      llm_chat.send(:run_callbacks, :before_tool_call, :tool_call, tool_call)
    end
  end
end
