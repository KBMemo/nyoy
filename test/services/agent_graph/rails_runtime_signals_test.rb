# frozen_string_literal: true

require "test_helper"

class AgentGraphRailsRuntimeSignalsTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
    @chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
    @run = AgentRun.create!(
      chat: @chat,
      graph_name: "test_graph",
      status: "running",
      current_node: "start",
      state: {}
    )
  end

  test "converts chat response cancellation to graph cancellation" do
    ChatResponseControl.cancel!(@chat)

    assert_raises(AgentGraph::Cancelled) do
      AgentGraph::RailsRuntimeSignals.new.check_cancelled!(@run)
    end
  end

  test "identifies legacy cancellation errors" do
    signals = AgentGraph::RailsRuntimeSignals.new

    assert signals.cancelled_exception?(ChatResponseControl::Cancelled.new)
    refute signals.cancelled_exception?(StandardError.new)
  end
end
