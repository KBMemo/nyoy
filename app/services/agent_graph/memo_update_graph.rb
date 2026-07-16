# frozen_string_literal: true

module AgentGraph
  class MemoUpdateGraph
    NAME = "memo_update"
    START = "plan_memo_update"

    def initialize
      @nodes = {
        "plan_memo_update" => Nodes::MemoUpdate::PlanMemoUpdate.new,
        "draft_memo_update" => Nodes::MemoUpdate::DraftMemoUpdate.new,
        "await_approval" => Nodes::MemoUpdate::AwaitApproval.new,
        "commit_memo_update" => Nodes::MemoUpdate::CommitMemoUpdate.new,
        "finalize_update_reply" => Nodes::MemoUpdate::FinalizeUpdateReply.new
      }.freeze
      @edges = {
        "plan_memo_update" => Edge.new(to: "draft_memo_update"),
        "draft_memo_update" => Edge.new(to: "await_approval"),
        "await_approval" => Edge.new(to: "commit_memo_update"),
        "commit_memo_update" => Edge.new(to: "finalize_update_reply"),
        "finalize_update_reply" => Edge.end
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
