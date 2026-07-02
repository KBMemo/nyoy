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
    stub_chat_ask_to_raise(@error) do
      assert_nothing_raised do
        ChatResponseJob.perform_now(@chat.id, "続きをお願い")
      end
    end

    message = @chat.messages.where(role: :assistant).order(:id).last
    assert message.chat_error?
    assert_includes message.chat_error_message, "会話が長すぎます"
  end

  private

  def stub_chat_ask_to_raise(error)
    original = Chat.instance_method(:ask)
    Chat.define_method(:ask) { |*, **| raise error }

    yield
  ensure
    Chat.define_method(:ask, original)
  end
end
