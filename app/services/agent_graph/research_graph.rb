# frozen_string_literal: true

module AgentGraph
  # R2 graph: plan → recall_memos → search_web → fetch_urls → synthesize_draft → finalize_answer
  # (evidence nodes are skipped via ResearchRouting when the plan does not need them)
  class ResearchGraph < GraphDefinition
    NAME = "research"
    START = "plan_research"

    def initialize
      super(
        name: NAME,
        start_node: START,
        nodes: {
          "plan_research" => Nodes::PlanResearch.new,
          "recall_memos" => Nodes::RecallMemos.new,
          "search_web" => Nodes::SearchWeb.new,
          "fetch_urls" => Nodes::FetchUrls.new,
          "synthesize_draft" => Nodes::SynthesizeDraft.new,
          "finalize_answer" => Nodes::FinalizeAnswer.new
        },
        edges: {
          "plan_research" => Edge.new(to: ->(state) { ResearchRouting.after_plan(state["plan"]) }),
          "recall_memos" => Edge.new(to: ->(state) { ResearchRouting.after_recall(state) }),
          "search_web" => Edge.new(to: ->(state) { ResearchRouting.after_search(state) }),
          "fetch_urls" => Edge.new(to: "synthesize_draft"),
          "synthesize_draft" => Edge.new(to: ->(state) { ResearchRouting.after_synthesize(state) }),
          "finalize_answer" => Edge.end
        },
        state_schema: ResearchStateSchema
      )
    end
  end
end
