# frozen_string_literal: true

module AgentGraph
  # R0 graph: plan_research → recall_memos → finalize_answer
  class ResearchGraph
    NAME = "research"
    START = "plan_research"

    def initialize
      @nodes = {
        "plan_research" => Nodes::PlanResearch.new,
        "recall_memos" => Nodes::RecallMemos.new,
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
