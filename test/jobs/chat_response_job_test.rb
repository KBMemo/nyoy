# frozen_string_literal: true

require "test_helper"

class ChatResponseJobTest < ActiveJob::TestCase
  setup do
    ChatModelCatalog.seed!
    @chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
    @error = RubyLLM::BadRequestError.new(
      nil,
      "request (16386 tokens) exceeds the available context size (16384 tokens), try increasing it"
    )
  end

  test "reports llm failures without re-raising" do
    @chat.messages.create!(role: :user, content: "続きをお願い")
    stub_chat_complete_to_raise(@error) do
      assert_nothing_raised do
        ChatResponseJob.perform_now(@chat.id)
      end
    end

    message = @chat.messages.where(role: :assistant).order(:id).last
    assert message.chat_error?
    assert_includes message.chat_error_message, "会話が長すぎます"
  end

  test "stream state accumulates text per assistant message" do
    state = ChatResponseJob::StreamState.new
    first = Message.new(id: 1)
    second = Message.new(id: 2)

    state.append_for(first, "Hello ")
    state.append_for(first, "world")
    state.append_for(second, "Next")

    assert_equal "Hello world", state.text_for(first)
    assert_equal "Next", state.text_for(second)
  end

  private

  def stub_chat_complete_to_raise(error)
    original = Chat.instance_method(:complete)
    Chat.define_method(:complete) { |*, **| raise error }

    yield
  ensure
    Chat.define_method(:complete, original)
  end
end
