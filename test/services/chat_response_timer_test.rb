# frozen_string_literal: true

require "test_helper"

class ChatResponseTimerTest < ActiveSupport::TestCase
  Chunk = Struct.new(:content, :thinking, keyword_init: true)

  test "records response and thinking elapsed time" do
    timer = ChatResponseTimer.new

    timer.observe_chunk!(Chunk.new(content: nil, thinking: Struct.new(:text).new("考え中")))
    sleep 0.01
    timer.observe_chunk!(Chunk.new(content: "回答", thinking: nil))
    sleep 0.01

    attrs = timer.message_timing_attributes

    assert_operator attrs[:response_elapsed_ms], :>=, 10
    assert_operator attrs[:thinking_elapsed_ms], :>=, 5
    assert_operator attrs[:thinking_elapsed_ms], :<=, attrs[:response_elapsed_ms]
  end

  test "records response time without thinking" do
    timer = ChatResponseTimer.new

    timer.observe_chunk!(Chunk.new(content: "回答", thinking: nil))

    attrs = timer.message_timing_attributes

    assert_operator attrs[:response_elapsed_ms], :>=, 0
    assert_nil attrs[:thinking_elapsed_ms]
  end

  test "records time to first chunk and passes through context build time" do
    timer = ChatResponseTimer.new
    sleep 0.01
    timer.observe_chunk!(Chunk.new(content: "最初", thinking: nil))
    timer.observe_chunk!(Chunk.new(content: "続き", thinking: nil))

    attrs = timer.message_timing_attributes(context_build_elapsed_ms: 42.4)

    assert_operator attrs[:first_chunk_elapsed_ms], :>=, 10
    assert_operator attrs[:first_chunk_elapsed_ms], :<=, attrs[:response_elapsed_ms]
    assert_equal 42, attrs[:context_build_elapsed_ms]
  end

  test "first chunk uses thinking output when it arrives first" do
    timer = ChatResponseTimer.new
    sleep 0.01
    timer.observe_chunk!(Chunk.new(content: nil, thinking: Struct.new(:text).new("考え中")))

    attrs = timer.message_timing_attributes

    assert_operator attrs[:first_chunk_elapsed_ms], :>=, 10
  end

  test "omits new metrics when unavailable" do
    timer = ChatResponseTimer.new
    timer.observe_chunk!(Chunk.new(content: "回答", thinking: nil))

    attrs = timer.message_timing_attributes

    assert_nil attrs[:context_build_elapsed_ms]
  end
end
