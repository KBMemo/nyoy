# frozen_string_literal: true

require "test_helper"

class AgentGraphNodesPlanResearchTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
    @chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
    @run = AgentRun.create!(
      chat: @chat,
      graph_name: AgentGraph::ResearchGraph::NAME,
      status: "running",
      current_node: "plan_research",
      state: {}
    )
  end

  teardown do
    AgentGraph::RoleServices.reset!
  end

  test "uses planner role and records the active profile" do
    calls = []
    planner = Object.new
    planner.define_singleton_method(:call) do |state:, run:, chat:|
      calls << { state: state, run: run, chat: chat }
      {
        need_memo: false,
        need_web: true,
        queries: [ "official docs" ],
        fetch_urls: [],
        sensitive: false
      }
    end

    result = AgentGraph::RoleServices.with(:planner, planner) do
      AgentGraph::Nodes::PlanResearch.new.call(
        state: { "question" => "仕様を確認して", "budget" => {} },
        run: @run,
        chat: @chat
      )
    end

    assert_equal "search_web", result.goto
    assert_equal "official docs", result.updates.dig("plan", "queries", 0)
    assert_equal "planner", result.updates.dig("planning", "role")
    assert_equal "override", result.updates.dig("planning", "profile")
    assert_equal 1, calls.size
    assert_same @run, calls.first.fetch(:run)
    assert_same @chat, calls.first.fetch(:chat)
  end
end
