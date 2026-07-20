# frozen_string_literal: true

require "test_helper"

class AgentGraphThinkingProgressTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  setup do
    ChatModelCatalog.seed!
    @chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
  end

  test "push throttles broadcasts and flush sends latest text" do
    progress = AgentGraph::ThinkingProgress.new(@chat)

    payloads = capture_broadcasts(ChatChannel.broadcasting_for(@chat)) do
      progress.push("a")
      progress.push("ab") # within throttle window
      progress.flush("abc")
    end

    types = payloads.map { |p| p["type"] }
    assert_equal %w[agent_run_progress_thinking agent_run_progress_thinking], types
    assert_equal "a", payloads.first["text"]
    assert_equal "abc", payloads.last["text"]
  end

  test "flush does not repeat the latest broadcast" do
    progress = AgentGraph::ThinkingProgress.new(@chat)

    payloads = capture_broadcasts(ChatChannel.broadcasting_for(@chat)) do
      progress.push("complete")
      progress.flush("complete")
    end

    assert_equal 1, payloads.size
    assert_equal "complete", payloads.first["text"]
  end
end
