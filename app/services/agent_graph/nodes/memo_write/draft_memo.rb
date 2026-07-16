# frozen_string_literal: true

module AgentGraph
  module Nodes
    module MemoWrite
      # Build display draft + structured memo_draft (no LLM polish).
      class DraftMemo
        def call(state:, run:, chat:)
          title = state["source_title"].to_s.strip.presence || "無題メモ"
          body = state["source_body"].to_s.strip
          if body.blank?
            return AgentGraph::NodeResult.fail("missing body for draft_memo")
          end

          memo_draft = {
            "action" => "create",
            "title" => title,
            "body" => body
          }
          draft = format_draft(title, body)

          AgentGraph::NodeResult.next(
            updates: {
              "memo_draft" => memo_draft,
              "draft" => draft
            }
          )
        end

        private

        def format_draft(title, body)
          <<~MD.strip
            ### #{title}

            #{body}
          MD
        end
      end
    end
  end
end
