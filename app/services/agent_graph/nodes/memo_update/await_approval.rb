# frozen_string_literal: true

module AgentGraph
  module Nodes
    module MemoUpdate
      class AwaitApproval
        REJECTED_MESSAGE = "メモ更新は却下されました。内容を直してから、もう一度更新を指示してください。"

        def call(state:, run:, chat:)
          case state["approval"].to_s
          when "approved", "not_required"
            AgentGraph::NodeResult.next("commit_memo_update")
          when "rejected"
            handle_rejection(chat)
          else
            if state["auto_approve"] == true
              AgentGraph::NodeResult.next(
                "commit_memo_update",
                updates: { "approval" => "approved" }
              )
            else
              AgentGraph::NodeResult.interrupt(
                updates: { "approval" => "pending" }
              )
            end
          end
        end

        private

        def handle_rejection(chat)
          message = AgentGraph::AssistantMessagePublisher.call(
            chat,
            content: REJECTED_MESSAGE
          )
          AgentGraph::NodeResult.end(
            updates: {
              "final_answer" => REJECTED_MESSAGE,
              "assistant_message_id" => message.id,
              "approval" => "rejected"
            }
          )
        end
      end
    end
  end
end
