# frozen_string_literal: true

require "test_helper"

class AgentGraphNodesSearchWebTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
    @chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
    @run = AgentRun.create!(
      chat: @chat,
      graph_name: AgentGraph::ResearchGraph::NAME,
      status: "running",
      current_node: "search_web",
      state: {}
    )
  end

  test "skips already searched queries and records newly searched queries" do
    calls = []
    stub_web_search(calls: calls, results: []) do
      result = AgentGraph::Nodes::SearchWeb.new.call(
        state: {
          "question" => "調べて",
          "plan" => {
            "need_web" => true,
            "queries" => [ "first query", "second query", "third query" ],
            "searched_queries" => [ "first query" ]
          },
          "search_results" => [],
          "budget" => {
            "searches_used" => 0,
            "max_searches" => 3,
            "fetches_used" => 0,
            "max_fetches" => 2,
            "fetched_urls" => []
          },
          "errors" => []
        },
        run: @run,
        chat: @chat
      )

      assert_equal [ "second query", "third query" ], calls
      assert_equal [ "first query", "second query", "third query" ], result.updates.dig("plan", "searched_queries")
    end
  end

  test "does not record a query as searched when search budget is exhausted" do
    calls = []
    stub_web_search(calls: calls, results: []) do
      result = AgentGraph::Nodes::SearchWeb.new.call(
        state: {
          "question" => "調べて",
          "plan" => {
            "need_web" => true,
            "queries" => [ "first query", "second query" ]
          },
          "search_results" => [],
          "budget" => {
            "searches_used" => 0,
            "max_searches" => 1,
            "fetches_used" => 0,
            "max_fetches" => 2,
            "fetched_urls" => []
          },
          "errors" => []
        },
        run: @run,
        chat: @chat
      )

      assert_equal [ "first query", "second query" ], calls
      assert_equal [ "first query" ], result.updates.dig("plan", "searched_queries")
      assert result.updates["errors"].any? { |error| error["query"] == "second query" }
    end
  end

  private

  def stub_web_search(calls:, results:)
    original = ChatTools::WebSearch.instance_method(:execute)
    ChatTools::WebSearch.define_method(:execute) do |q:, limit: nil|
      calls << q
      if (error = @budget.consume_search!)
        error
      else
        { "query" => q, "results" => results, "number_of_results" => results.size }
      end
    end
    yield
  ensure
    ChatTools::WebSearch.define_method(:execute, original)
  end
end
