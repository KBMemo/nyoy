# frozen_string_literal: true

module AgentGraph
  # R2 graph: plan → recall_memos → search_web → fetch_urls → synthesize_draft → finalize_answer
  # (await_approval remains registered for legacy pending runs / resume)
  # (evidence nodes are skipped via ResearchRouting when the plan does not need them)
  class ResearchGraph
    NAME = "research"
    START = "plan_research"

    def initialize
      @nodes = {
        "plan_research" => Nodes::PlanResearch.new,
        "recall_memos" => Nodes::RecallMemos.new,
        "search_web" => Nodes::SearchWeb.new,
        "fetch_urls" => Nodes::FetchUrls.new,
        "synthesize_draft" => Nodes::SynthesizeDraft.new,
        "await_approval" => Nodes::AwaitApproval.new,
        "finalize_answer" => Nodes::FinalizeAnswer.new
      }.freeze
      @edges = {
        "plan_research" => Edge.new(to: ->(state) { ResearchRouting.after_plan(state["plan"]) }),
        "recall_memos" => Edge.new(to: ->(state) { ResearchRouting.after_recall(state) }),
        "search_web" => Edge.new(to: ->(state) { ResearchRouting.after_search(state) }),
        "fetch_urls" => Edge.new(to: "synthesize_draft"),
        "synthesize_draft" => Edge.new(to: ->(state) { ResearchRouting.after_synthesize(state) }),
        "await_approval" => Edge.new(to: "finalize_answer"),
        "finalize_answer" => Edge.end
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

    def next_node_for(name, state)
      edge = @edges[name.to_s]
      raise "missing edge for node: #{name}" unless edge

      edge.next_node(state)
    end
  end
end
