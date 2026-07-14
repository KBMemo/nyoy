# frozen_string_literal: true

require "test_helper"

class AgentGraphProgressBroadcasterTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  setup do
    ChatModelCatalog.seed!
    @chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
  end

  test "started broadcasts labeled progress html" do
    assert_broadcasts(ChatChannel.broadcasting_for(@chat), 1) do
      AgentGraph::ProgressBroadcaster.started!(@chat, "search_web")
    end

    payload = capture_broadcasts(ChatChannel.broadcasting_for(@chat)) do
      AgentGraph::ProgressBroadcaster.started!(@chat, "search_web")
    end.last

    assert_equal "research_progress", payload["type"]
    assert_includes payload["label"], "Web"
    assert_includes payload["html"], "research_progress_panel"
    assert_includes payload["html"], "Web"
  end

  test "clear broadcasts empty panel" do
    payload = capture_broadcasts(ChatChannel.broadcasting_for(@chat)) do
      AgentGraph::ProgressBroadcaster.clear!(@chat)
    end.last

    assert_equal "research_progress", payload["type"]
    assert_nil payload["label"]
    assert_equal "", payload["html"]
  end
end
