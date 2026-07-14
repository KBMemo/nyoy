# frozen_string_literal: true

module AgentGraph
  # R1 graph: plan → recall_memos → search_web → fetch_urls → finalize_answer
  # (nodes are skipped via ResearchRouting when the plan does not need them)
  class ResearchGraph
    NAME = "research"
    START = "plan_research"

    def initialize
      @nodes = {
        "plan_research" => Nodes::PlanResearch.new,
        "recall_memos" => Nodes::RecallMemos.new,
        "search_web" => Nodes::SearchWeb.new,
        "fetch_urls" => Nodes::FetchUrls.new,
        "finalize_answer" => Nodes::FinalizeAnswer.new
      }.freeze
    end

    def name
      NAME
    end

    def start_node
      START
    end

    def node_for(name)
      @nodes[name.to_s]
    end
  end
end
