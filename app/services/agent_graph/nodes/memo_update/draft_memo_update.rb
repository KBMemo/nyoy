# frozen_string_literal: true

module AgentGraph
  module Nodes
    module MemoUpdate
      class DraftMemoUpdate
        def call(state:, run:, chat:)
          memo_ref = state["memo_ref"].to_s
          original = state["original_memo"].is_a?(Hash) ? state["original_memo"] : {}
          updated_at = original["updated_at"].to_s.presence
          if updated_at.blank?
            return AgentGraph::NodeResult.fail("get_memo returned no updated_at")
          end

          mode = state.dig("plan", "mode").to_s == "replace" ? "replace" : "append"
          body = state["source_body"].to_s
          title = state["source_title"].to_s.presence
          memo_draft = {
            "action" => "update",
            "mode" => mode,
            "memo_ref" => memo_ref,
            "updated_at" => updated_at,
            "title" => title,
            "body" => mode == "replace" ? body : nil,
            "append_body" => mode == "append" ? body : nil
          }.compact

          AgentGraph::NodeResult.next(
            updates: {
              "memo_draft" => memo_draft,
              "draft" => format_draft(original, memo_draft)
            }
          )
        end

        private

        def format_draft(original, draft)
          title = original["title"].presence || draft["memo_ref"]
          mode_label = draft["mode"] == "replace" ? "本文を置換" : "本文末尾に追記"
          body = draft["body"].presence || draft["append_body"].presence || "(本文変更なし)"
          lines = [
            "### #{title}",
            "",
            "- 対象: `#{draft["memo_ref"]}`",
            "- 操作: #{mode_label}",
            draft["title"].present? ? "- 新タイトル: #{draft["title"]}" : nil,
            "",
            body
          ].compact
          lines.join("\n")
        end
      end
    end
  end
end
