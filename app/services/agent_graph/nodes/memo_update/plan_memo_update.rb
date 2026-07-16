# frozen_string_literal: true

module AgentGraph
  module Nodes
    module MemoUpdate
      class PlanMemoUpdate
        UPDATE_PHRASE = Regexp.union(
          /update[_ ]?memo/i,
          /メモ(を)?(更新|追記|書き換|修正)(して)?(ください|下さい)?/,
          /徒然(を|に)?(更新|追記|書き換|修正)(して)?(ください|下さい)?/,
          /(更新|追記|書き換|修正)(して|してください|して下さい)/
        )

        MEMO_REF_PATTERNS = [
          /(?:memo|メモ|徒然|uid|id|ref)[:：#\s]*([0-9A-Za-z][0-9A-Za-z_-]{0,40})/i,
          /([0-9]{1,12})\s*(?:番|の)?\s*(?:メモ|徒然)/
        ].freeze

        def call(state:, run:, chat:)
          memo_ref = resolve_memo_ref(state)
          if memo_ref.blank?
            return AgentGraph::NodeResult.fail(
              "更新対象のメモが特定できません。memo_ref またはメモ id/uid を指定してください。"
            )
          end

          original = ChatTools::GetMemo.new.execute(memo_ref: memo_ref)
          if original.is_a?(Hash) && original["error"].present?
            return AgentGraph::NodeResult.fail(
              "get_memo failed: #{original["error"]}",
              updates: error_update(state, "GET_MEMO_FAILED", original["error"])
            )
          end

          body_source, body = resolve_body(state, chat)
          title = state["mcp_title"].to_s.strip.presence
          if body.blank? && title.blank?
            return AgentGraph::NodeResult.fail(
              "更新する内容がありません。追記本文、置換本文、または新しいタイトルを指定してください。"
            )
          end

          mode = resolve_mode(state)
          plan = {
            "action" => "update",
            "mode" => mode,
            "memo_ref_source" => state["mcp_memo_ref"].present? ? "mcp" : "instruction",
            "body_source" => body_source,
            "title_source" => title.present? ? "mcp" : nil
          }

          AgentGraph::NodeResult.next(
            updates: {
              "intent" => "memo_update",
              "plan" => plan,
              "memo_ref" => memo_ref,
              "source_body" => body,
              "source_title" => title,
              "original_memo" => original.is_a?(Hash) ? original : { "raw" => original }
            }
          )
        end

        private

        def resolve_memo_ref(state)
          explicit = state["mcp_memo_ref"].to_s.strip
          return explicit if explicit.present?

          text = state["instruction"].to_s
          MEMO_REF_PATTERNS.each do |pattern|
            match = text.match(pattern)
            return match[1].to_s if match
          end
          nil
        end

        def resolve_body(state, chat)
          mcp = state["mcp_body"].to_s.strip
          return [ "mcp", mcp ] if mcp.present?

          leftover = strip_update_phrases(state["instruction"].to_s)
          return [ "instruction", leftover ] if leftover.present?

          assistant = latest_assistant_body(chat)
          return [ "assistant", assistant ] if assistant.present?

          [ nil, nil ]
        end

        def resolve_mode(state)
          mode = state["mcp_mode"].to_s.strip
          return mode if %w[append replace].include?(mode)

          text = state["instruction"].to_s
          return "replace" if text.match?(/置換|置き換|書き換|replace/i)

          "append"
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

        def strip_update_phrases(text)
          stripped = text.to_s.gsub(UPDATE_PHRASE, "")
          MEMO_REF_PATTERNS.each { |pattern| stripped = stripped.gsub(pattern, "") }
          stripped = stripped.gsub(/\A\s*(に|へ|を)\s*/m, "")
          stripped.gsub(/\A[\s、。．!！?？:：]+|[\s、。．!！?？:：]+\z/, "").strip
        end

        def error_update(state, code, message)
          {
            "errors" => Array(state["errors"]) + [ {
              "code" => code,
              "message" => message.to_s
            } ]
          }
        end
      end
    end
  end
end
