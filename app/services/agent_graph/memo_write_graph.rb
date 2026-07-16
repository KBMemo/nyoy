# frozen_string_literal: true

module AgentGraph
  # Create-only memo write: plan → draft → approve → commit → finalize.
  class MemoWriteGraph < GraphDefinition
    NAME = "memo_write"
    START = "plan_memo_write"

    def initialize
      super(
        name: NAME,
        start_node: START,
        nodes: {
          "plan_memo_write" => Nodes::MemoWrite::PlanMemoWrite.new,
          "draft_memo" => Nodes::MemoWrite::DraftMemo.new,
          "await_approval" => Nodes::ApprovalGate.new(
            approved_goto: "commit_memo",
            rejected_message: "メモ保存は却下されました。内容を直してから、もう一度「徒然に保存して」と伝えてください。"
          ),
          "commit_memo" => Nodes::MemoWrite::CommitMemo.new,
          "finalize_reply" => Nodes::MemoWrite::FinalizeReply.new
        },
        edges: {
          "plan_memo_write" => Edge.new(to: "draft_memo"),
          "draft_memo" => Edge.new(to: "await_approval"),
          "await_approval" => Edge.new(to: "commit_memo"),
          "commit_memo" => Edge.new(to: "finalize_reply"),
          "finalize_reply" => Edge.end
        },
        state_schema: MemoWriteStateSchema
      )
    end
  end
end
