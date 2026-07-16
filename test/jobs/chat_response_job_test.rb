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

  test "marks assistant truncated when finish_reason is length" do
    @chat.update!(response_state: "running")
    @chat.messages.create!(role: :user, content: "普通の挨拶")

    stub_chat_complete_truncated_by_length(thinking: "途中まで考えた…") do
      assert_nothing_raised do
        ChatResponseJob.perform_now(@chat.id)
      end
    end

    assistants = @chat.messages.where(role: :assistant).order(:id)
    partial = assistants.find { |m| !m.chat_error? }
    error = assistants.find(&:chat_error?)

    assert partial.present?
    assert partial.truncated?
    assert_equal "途中まで考えた…", partial.thinking_text
    assert error.present?
    assert_includes error.chat_error_message, "打ち切"
    assert_equal "idle", @chat.reload.response_state
  end

  test "treats thread-local length finish_reason as truncation" do
    @chat.update!(response_state: "running")
    @chat.messages.create!(role: :user, content: "普通の挨拶")

    original = Chat.instance_method(:complete)
    Chat.define_method(:complete) do |*, **, &block|
      messages.create!(role: :assistant, content: "")
      chunk = Object.new
      chunk.define_singleton_method(:content) { "途中まで" }
      chunk.define_singleton_method(:thinking) { nil }
      chunk.define_singleton_method(:tool_call?) { false }
      # finish_reason not on chunk — only thread-local (simulates late SSE)
      Nyoy::FinishReasonCapture.record!("length")
      block&.call(chunk)
    end

    assert_nothing_raised { ChatResponseJob.perform_now(@chat.id) }

    assert @chat.messages.where(role: :assistant).any?(&:truncated?)
    assert @chat.messages.where(role: :assistant).any?(&:chat_error?)
  ensure
    Chat.define_method(:complete, original)
  end

  test "delegates research intent turns to ResearchGraphRunner" do
    @chat.update!(response_state: "running")
    @chat.messages.create!(role: :user, content: "調査日の根拠はどこから？")

    called = false
    original = AgentGraph::ResearchGraphRunner.method(:call)
    AgentGraph::ResearchGraphRunner.define_singleton_method(:call) do |chat|
      called = true
      chat.messages.create!(role: :assistant, content: "graph answer")
      AgentRun.create!(
        chat: chat,
        graph_name: "research",
        status: "completed",
        state: { "final_answer" => "graph answer" },
        finished_at: Time.current
      )
    end

    assert_nothing_raised do
      ChatResponseJob.perform_now(@chat.id)
    end

    assert called
    assert_equal "idle", @chat.reload.response_state
    assert_equal "graph answer", @chat.messages.where(role: :assistant).order(:id).last.content
  ensure
    AgentGraph::ResearchGraphRunner.define_singleton_method(:call, original) if defined?(original)
  end

  test "surfaces Research Graph failures as chat errors" do
    @chat.update!(response_state: "running")
    @chat.messages.create!(role: :user, content: "調査の根拠は？")

    original = AgentGraph::ResearchGraphRunner.method(:call)
    AgentGraph::ResearchGraphRunner.define_singleton_method(:call) do |chat|
      AgentRun.create!(
        chat: chat,
        graph_name: "research",
        status: "failed",
        error_message: "empty draft",
        state: { "question" => "調査の根拠は？" },
        finished_at: Time.current
      )
    end

    assert_nothing_raised do
      ChatResponseJob.perform_now(@chat.id)
    end

    message = @chat.messages.where(role: :assistant).order(:id).last
    assert message.chat_error?
    assert_includes message.chat_error_message, "調査フローが失敗しました"
    assert_includes message.chat_error_message, "empty draft"
  ensure
    AgentGraph::ResearchGraphRunner.define_singleton_method(:call, original) if defined?(original)
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

  test "persist_assistant_timing writes token usage from streamed chunks" do
    job = ChatResponseJob.new
    message = @chat.messages.create!(role: :assistant, content: "完了")
    timer = ChatResponseTimer.new
    chunk = Object.new
    chunk.define_singleton_method(:content) { nil }
    chunk.define_singleton_method(:thinking) { nil }
    chunk.define_singleton_method(:usage) do
      {
        "prompt_tokens" => 160,
        "completion_tokens" => 40,
        "prompt_tokens_details" => {
          "cached_tokens" => 120,
          "cache_creation_tokens" => 30
        }
      }
    end
    timer.observe_chunk!(chunk)

    job.send(:persist_assistant_timing, @chat, timer)

    message.reload
    assert_equal 160, message.input_tokens
    assert_equal 40, message.output_tokens
    assert_equal 120, message.cached_tokens
    assert_equal 30, message.cache_creation_tokens
  end

  test "persist_assistant_timing writes llama cache metadata" do
    job = ChatResponseJob.new
    message = @chat.messages.create!(role: :assistant, content: "完了")
    timer = ChatResponseTimer.new
    @chat.instance_variable_set(:@llama_cache_metadata, {
      enabled: true,
      cache_prompt: true,
      slot_id: 2,
      slot_count: 4
    })

    job.send(:persist_assistant_timing, @chat, timer)

    message.reload
    assert_equal true, message.llama_cache_prompt
    assert_equal 2, message.llama_cache_slot_id
    assert_equal 4, message.llama_cache_slot_count
  end

  test "writable_message_attrs skips columns unknown to current process" do
    job = ChatResponseJob.new
    message = Object.new
    message.define_singleton_method(:has_attribute?) { |name| name.to_sym == :response_elapsed_ms }

    attrs = job.send(:writable_message_attrs, message, {
      response_elapsed_ms: 100,
      llama_cache_prompt: true
    })

    assert_equal({ response_elapsed_ms: 100 }, attrs)
  end

  test "current_assistant_message ignores newer tool call messages" do
    job = ChatResponseJob.new
    answer = @chat.messages.create!(role: :assistant, content: "回答")
    tool_call = @chat.messages.create!(role: :assistant, content: "")
    tool_call.tool_calls_association.create!(
      tool_call_id: "call_test",
      name: "fetch_url",
      arguments: { "url" => "https://example.com" }
    )

    assert_equal answer, job.send(:current_assistant_message, @chat, nil)
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
    message.define_singleton_method(:broadcast_rendered_content!) do |text, seq: nil|
      content_broadcasts << [ text, seq ]
    end
    message.define_singleton_method(:broadcast_refresh!) do |**kwargs|
      refresh_broadcasts << kwargs
    end
    message.define_singleton_method(:broadcast_rendered_thinking!) { |*| }

    job.send(:broadcast_assistant_message!, message, stream_state: state)

    assert_equal "1行目\n2行目", content_broadcasts.first.first
    assert content_broadcasts.first.second
    assert_equal "1行目\n2行目", refresh_broadcasts.first[:content]
    assert refresh_broadcasts.first[:seq]
    assert_operator refresh_broadcasts.first[:seq], :>, content_broadcasts.first.second
  end

  private

  class RecordingMessage
    attr_reader :id, :content_broadcasts, :thinking_broadcasts

    def initialize(id)
      @id = id
      @content_broadcasts = []
      @thinking_broadcasts = []
    end

    def broadcast_rendered_content!(text, seq: nil)
      @content_broadcasts << text.dup
    end

    def broadcast_rendered_thinking!(text, seq: nil)
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

  def stub_chat_complete_truncated_by_length(thinking:, content: nil)
    original = Chat.instance_method(:complete)
    Chat.define_method(:complete) do |*, **, &block|
      messages.create!(role: :assistant, content: "")
      thinking_chunk = Object.new
      thinking_chunk.define_singleton_method(:content) { nil }
      thinking_chunk.define_singleton_method(:thinking) do
        Struct.new(:text).new(thinking)
      end
      thinking_chunk.define_singleton_method(:finish_reason) { nil }
      thinking_chunk.define_singleton_method(:tool_call?) { false }

      block&.call(thinking_chunk)

      if content
        content_chunk = Object.new
        content_chunk.define_singleton_method(:content) { content }
        content_chunk.define_singleton_method(:thinking) { nil }
        content_chunk.define_singleton_method(:finish_reason) { nil }
        content_chunk.define_singleton_method(:tool_call?) { false }
        block&.call(content_chunk)
      end

      finish_chunk = Object.new
      finish_chunk.define_singleton_method(:content) { nil }
      finish_chunk.define_singleton_method(:thinking) { nil }
      finish_chunk.define_singleton_method(:finish_reason) { "length" }
      finish_chunk.define_singleton_method(:tool_call?) { false }
      block&.call(finish_chunk)
    end

    yield
  ensure
    Chat.define_method(:complete, original)
  end
end
