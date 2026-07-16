# frozen_string_literal: true

require "test_helper"

class AgentGraphNodeResultTest < ActiveSupport::TestCase
  test "next without goto delegates routing to graph edge" do
    result = AgentGraph::NodeResult.next(updates: { foo: "bar" })

    refute result.explicit_goto?
    refute result.finished?
    assert_nil result.goto
  end

  test "end explicitly finishes" do
    result = AgentGraph::NodeResult.end

    assert result.explicit_goto?
    assert result.finished?
    assert_nil result.goto
  end

  test "next with goto remains explicit" do
    result = AgentGraph::NodeResult.next("next_node")

    assert result.explicit_goto?
    refute result.finished?
    assert_equal "next_node", result.goto
  end
end
