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
