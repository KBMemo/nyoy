# frozen_string_literal: true

require "minitest/autorun"
require "agent_graph/core"

class AgentGraphCoreVersionTest < Minitest::Test
  def test_exposes_the_package_version
    assert_equal "0.1.0", AgentGraph::Core::VERSION
  end
end
