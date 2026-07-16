# frozen_string_literal: true

module AgentGraph
  # Create-only memo write: plan → draft → approve → commit → finalize.
  class MemoWriteGraph
    NAME = "memo_write"
    START = "plan_memo_write"

    def initialize
      @nodes = {
        "plan_memo_write" => Nodes::MemoWrite::PlanMemoWrite.new,
        "draft_memo" => Nodes::MemoWrite::DraftMemo.new,
        "await_approval" => Nodes::MemoWrite::AwaitApproval.new,
        "commit_memo" => Nodes::MemoWrite::CommitMemo.new,
        "finalize_reply" => Nodes::MemoWrite::FinalizeReply.new
      }.freeze
      @edges = {
        "plan_memo_write" => Edge.new(to: "draft_memo"),
        "draft_memo" => Edge.new(to: "await_approval"),
        "await_approval" => Edge.new(to: "commit_memo"),
        "commit_memo" => Edge.new(to: "finalize_reply"),
        "finalize_reply" => Edge.end
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
