# frozen_string_literal: true

module AgentGraph
  module Nodes
    module MemoWrite
      # Resolve create-only plan and body/title sources.
      class PlanMemoWrite
        SAVE_PHRASE = Regexp.union(
          /徒然に保存(して)?(ください|下さい)?/,
          /徒然(メモ)?に書いて(ください|下さい)?/,
          /徒然メモ(を)?(作|書|保存)(って|いて|して)?(ください|下さい)?/,
          /メモに保存(して)?(ください|下さい)?/,
          /メモにして(ください|下さい)?/,
          /メモを作(って|成して)?(ください|下さい)?/,
          /メモを書いて(ください|下さい)?/,
          /メモとして保存(して)?(ください|下さい)?/,
          /これを(徒然|メモ)(に)?(保存)?(して)?(ください|下さい)?/,
          /この(回答|内容|メッセージ|草案|ドラフト)を.*(保存|メモ|徒然).*/,
          /create[_ ]?memo/i,
          /\bsave (this |it )?(as |to )?(a )?memo\b/i,
          /\bsave (this |it )?to tsurezure\b/i
        )

        def call(state:, run:, chat:)
          body_source, body = resolve_body(state, chat)
          if body.blank?
            return AgentGraph::NodeResult.fail(
              "保存する内容がありません。先に保存したい文章がある状態で「徒然に保存して」と伝えてください。"
            )
          end

          title = state["mcp_title"].presence || infer_title(body)
          plan = {
            "action" => "create",
            "body_source" => body_source,
            "title_source" => state["mcp_title"].present? ? "mcp" : "inferred"
          }

          AgentGraph::NodeResult.next(
            updates: {
              "intent" => "memo_write",
              "plan" => plan,
              "source_body" => body,
              "source_title" => title
            }
          )
        end

        private

        def resolve_body(state, chat)
          mcp = state["mcp_body"].to_s.strip
          return [ "mcp", mcp ] if mcp.present?

          assistant = latest_assistant_body(chat)
          return [ "assistant", assistant ] if assistant.present?

          leftover = strip_save_phrases(state["instruction"].to_s)
          return [ "instruction", leftover ] if leftover.present?

          [ nil, nil ]
        end

        def latest_assistant_body(chat)
          chat.messages
            .where(role: :assistant)
            .reorder(id: :desc)
            .limit(8)
            .detect { |message| !message.tool_call_message? && message.content.to_s.strip.present? }
            &.content
            .to_s
            .strip
            .presence
        end

        def strip_save_phrases(text)
          text.to_s.gsub(SAVE_PHRASE, "").gsub(/\A[\s、。．!！?？:：]+|[\s、。．!！?？:：]+\z/, "").strip
        end

        def infer_title(body)
          heading = body.lines.map(&:strip).find { |line| line.start_with?("# ") }
          return heading.delete_prefix("# ").strip.truncate(80) if heading.present?

          body.lines.map(&:strip).find(&:present?).to_s.truncate(80).presence || "無題メモ"
        end
      end
    end
  end
end
