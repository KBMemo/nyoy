# frozen_string_literal: true

module AgentGraph
  class MemoUpdateGraph < GraphDefinition
    NAME = "memo_update"
    START = "plan_memo_update"

    def initialize
      super(
        name: NAME,
        start_node: START,
        nodes: {
          "plan_memo_update" => Nodes::MemoUpdate::PlanMemoUpdate.new,
          "draft_memo_update" => Nodes::MemoUpdate::DraftMemoUpdate.new,
          "await_approval" => Nodes::ApprovalGate.new(
            approved_goto: "commit_memo_update",
            rejected_message: "メモ更新は却下されました。内容を直してから、もう一度更新を指示してください。"
          ),
          "commit_memo_update" => Nodes::MemoUpdate::CommitMemoUpdate.new,
          "finalize_update_reply" => Nodes::MemoUpdate::FinalizeUpdateReply.new
        },
        edges: {
          "plan_memo_update" => Edge.new(to: "draft_memo_update"),
          "draft_memo_update" => Edge.new(to: "await_approval"),
          "await_approval" => Edge.new(to: "commit_memo_update"),
          "commit_memo_update" => Edge.new(to: "finalize_update_reply"),
          "finalize_update_reply" => Edge.end
        },
        state_schema: MemoUpdateStateSchema
      )
    end
  end
end
