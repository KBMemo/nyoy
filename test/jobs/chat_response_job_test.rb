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

  test "reports cancellation without re-raising" do
    @chat.update!(response_state: "running")
    @chat.messages.create!(role: :user, content: "続きをお願い")

    stub_chat_complete_to_raise(ChatResponseControl::Cancelled.new) do
      assert_nothing_raised do
        ChatResponseJob.perform_now(@chat.id)
      end
    end

    message = @chat.messages.where(role: :assistant).order(:id).last
    assert message.chat_cancelled?
    assert_equal "idle", @chat.reload.response_state
  end

  test "cancelled before streaming still creates a cancellation message" do
    @chat.update!(response_state: "cancelled")
    @chat.messages.create!(role: :user, content: "やっぱり中止")

    assert_nothing_raised do
      ChatResponseJob.perform_now(@chat.id)
    end

    message = @chat.messages.where(role: :assistant).order(:id).last
    assert message.chat_cancelled?
    assert_equal "idle", @chat.reload.response_state
  end

  test "logs the underlying error before surfacing a friendly message" do
    @chat.messages.create!(role: :user, content: "続きをお願い")

    logged = []
    original_logger = Rails.logger
    Rails.logger = Class.new do
      define_method(:error) { |msg| logged << msg.to_s }
      def method_missing(*) = nil
      def respond_to_missing?(*) = true
    end.new

    begin
      stub_chat_complete_to_raise(NoMethodError.new("undefined method 'foo'")) do
        assert_nothing_raised do
          ChatResponseJob.perform_now(@chat.id)
        end
      end
    ensure
      Rails.logger = original_logger
    end

    assert(logged.any? { |line| line.include?("NoMethodError") }, "expected the real error to be logged")

    message = @chat.messages.where(role: :assistant).order(:id).last
    assert message.chat_error?
  end

  test "keeps the partial answer and marks it cancelled when interrupted mid-stream" do
    @chat.update!(response_state: "running")
    @chat.messages.create!(role: :user, content: "長い説明をお願い")

    stub_chat_complete_streaming_then_cancel(content: "途中までの回答") do
      assert_nothing_raised do
        ChatResponseJob.perform_now(@chat.id)
      end
    end

    message = @chat.messages.where(role: :assistant).order(:id).last
    assert message.cancelled?, "partial answer should be flagged as cancelled"
    assert_equal "途中までの回答", message.content
    refute message.chat_cancelled?, "should stay a normal assistant bubble, not a cancel notice"
    assert_equal "idle", @chat.reload.response_state
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

  test "stream state preserves newline-only chunks" do
    state = ChatResponseJob::StreamState.new
    message = Message.new(id: 1)

    state.append_for(message, "1行目")
    state.append_for(message, "\n")
    state.append_for(message, "2行目")

    assert_equal "1行目\n2行目", state.text_for(message)
  end

  test "streamable_text keeps whitespace-only chunks that present? would drop" do
    job = ChatResponseJob.new

    refute "\n".present?
    assert job.send(:streamable_text?, "\n")
    assert job.send(:streamable_text?, " ")
    refute job.send(:streamable_text?, nil)
    refute job.send(:streamable_text?, "")
  end

  test "stream state accumulates thinking text per assistant message" do
    state = ChatResponseJob::StreamState.new
    first = Message.new(id: 1)
    second = Message.new(id: 2)

    state.append_thinking_for(first, "考え")
    state.append_thinking_for(first, "中")
    state.append_thinking_for(second, "別")

    assert_equal "考え中", state.thinking_for(first)
    assert_equal "別", state.thinking_for(second)
  end

  test "broadcast_content debounces rapid updates and flush forces the final one" do
    state = ChatResponseJob::StreamState.new
    message = RecordingMessage.new(1)

    state.append_for(message, "a")
    state.broadcast_content(message)
    state.append_for(message, "b")
    state.broadcast_content(message)

    assert_equal [ "a" ], message.content_broadcasts, "second update within the interval is coalesced"

    state.flush(message)

    assert_equal [ "a", "ab" ], message.content_broadcasts, "flush emits the latest accumulated text"
  end

  test "broadcast helpers skip empty buffers" do
    state = ChatResponseJob::StreamState.new
    message = RecordingMessage.new(1)

    state.flush(message)

    assert_empty message.content_broadcasts
    assert_empty message.thinking_broadcasts
  end

  test "persist_streamed_state saves accumulated text when db lags behind stream" do
    job = ChatResponseJob.new
    message = @chat.messages.create!(role: :assistant, content: "短")
    state = ChatResponseJob::StreamState.new
    state.append_for(message, "い本文")

    job.send(:persist_streamed_state!, message, state)

    assert_equal "い本文", message.reload.content
  end

  test "persist_streamed_state preserves newlines from streamed chunks" do
    job = ChatResponseJob.new
    message = @chat.messages.create!(role: :assistant, content: "")
    state = ChatResponseJob::StreamState.new
    state.append_for(message, "1行目")
    state.append_for(message, "\n")
    state.append_for(message, "2行目")

    job.send(:persist_streamed_state!, message, state)

    assert_equal "1行目\n2行目", message.reload.content
  end

  test "persist_assistant_timing writes timing columns without callbacks" do
    job = ChatResponseJob.new
    message = @chat.messages.create!(role: :assistant, content: "完了")
    timer = ChatResponseTimer.new
    timer.instance_variable_set(:@first_chunk_elapsed_ms, 120)

    job.send(:persist_assistant_timing, @chat, timer)

    message.reload
    assert_equal 120, message.first_chunk_elapsed_ms
    assert_equal "完了", message.content
  end

  test "broadcast_assistant_message uses stream text when db content is still empty" do
    job = ChatResponseJob.new
    message = @chat.messages.create!(role: :assistant, content: "")
    state = ChatResponseJob::StreamState.new
    state.append_for(message, "1行目")
    state.append_for(message, "\n")
    state.append_for(message, "2行目")

    content_broadcasts = []
    refresh_broadcasts = []
    message.define_singleton_method(:broadcast_rendered_content!) do |text|
      content_broadcasts << text
    end
    message.define_singleton_method(:broadcast_refresh!) do |**kwargs|
      refresh_broadcasts << kwargs
    end
    message.define_singleton_method(:broadcast_rendered_thinking!) { |*| }

    job.send(:broadcast_assistant_message!, message, stream_state: state)

    assert_equal [ "1行目\n2行目" ], content_broadcasts
    assert_equal "1行目\n2行目", refresh_broadcasts.first[:content]
  end

  private

  class RecordingMessage
    attr_reader :id, :content_broadcasts, :thinking_broadcasts

    def initialize(id)
      @id = id
      @content_broadcasts = []
      @thinking_broadcasts = []
    end

    def broadcast_rendered_content!(text)
      @content_broadcasts << text.dup
    end

    def broadcast_rendered_thinking!(text)
      @thinking_broadcasts << text.dup
    end
  end

  def stub_chat_complete_to_raise(error)
    original = Chat.instance_method(:complete)
    Chat.define_method(:complete) { |*, **| raise error }

    yield
  ensure
    Chat.define_method(:complete, original)
  end

  def stub_chat_complete_streaming_then_cancel(content:)
    original = Chat.instance_method(:complete)
    Chat.define_method(:complete) do |*, **, &block|
      messages.create!(role: :assistant, content: "")
      chunk = Struct.new(:content, :thinking).new(content, nil)
      block&.call(chunk)
      raise ChatResponseControl::Cancelled
    end

    yield
  ensure
    Chat.define_method(:complete, original)
  end
end
