# frozen_string_literal: true

module AgentGraph
  # Thin progress line for Research / MemoWrite Graph node execution (Cable → chat UI).
  class ProgressBroadcaster
    LABELS = {
      "plan_research" => "調査計画を作成しています…",
      "recall_memos" => "関連メモを検索しています…",
      "search_web" => "Web を検索しています…",
      "fetch_urls" => "ページを取得しています…",
      "evaluate_evidence" => "根拠の十分性を確認しています…",
      "synthesize_draft" => "根拠を整理しています…",
      "await_approval" => "ドラフトの承認待ちです…",
      "finalize_answer" => "最終回答を生成しています…",
      "plan_memo_write" => "メモ保存の準備をしています…",
      "draft_memo" => "メモ草案を作成しています…",
      "commit_memo" => "徒然に保存しています…",
      "finalize_reply" => "保存結果を反映しています…",
      "plan_memo_update" => "メモ更新の準備をしています…",
      "draft_memo_update" => "メモ更新案を作成しています…",
      "commit_memo_update" => "徒然メモを更新しています…",
      "finalize_update_reply" => "更新結果を反映しています…"
    }.freeze

    # Nodes that actually call an LLM (show model name in the progress panel).
    LLM_NODES = %w[draft_memo finalize_answer finalize_reply].freeze
    MAX_THINKING_BROADCAST_CHARS = 16_000
    TRUNCATED_THINKING_PREFIX = "…\n".freeze

    class << self
      def started!(chat, node_name, agent_run: nil)
        node = node_name.to_s
        node_started_at = Time.current.iso8601(3)
        run_started_at = agent_run&.started_at&.iso8601(3)

        broadcast(
          chat,
          label: label_for(node),
          model_name: model_name_for(node, chat),
          node_name: node,
          node_started_at: node_started_at,
          run_started_at: run_started_at
        )
      end

      def render_for_run(agent_run)
        return "" unless agent_run&.running?

        node = agent_run.current_node.to_s
        render_panel(
          label: label_for(node),
          model_name: model_name_for(node, agent_run.chat),
          node_started_at: node_started_at_for(agent_run)&.iso8601(3) || Time.current.iso8601(3),
          run_started_at: agent_run.started_at&.iso8601(3)
        )
      end

      # Live thinking for finalize_answer (does not replace the panel / clock).
      def thinking!(chat, text)
        body = bounded_thinking(text)
        return if body.blank?

        ChatChannel.broadcast_to(chat, {
          type: "agent_run_progress_thinking",
          text: body
        })
      end

      # Show the LLM system / user prompts in the progress panel (finalize_answer).
      def prompts!(chat, system:, user: nil)
        system_text = system.to_s.strip
        user_text = user.to_s.strip
        return if system_text.blank? && user_text.blank?

        ChatChannel.broadcast_to(chat, {
          type: "agent_run_progress_prompts",
          system: system_text.presence,
          user: user_text.presence
        }.compact)
      end

      def clear!(chat)
        broadcast(chat, label: nil)
      end

      private

      def bounded_thinking(text)
        body = text.to_s
        return body if body.length <= MAX_THINKING_BROADCAST_CHARS

        "#{TRUNCATED_THINKING_PREFIX}#{body.last(MAX_THINKING_BROADCAST_CHARS)}"
      end

      def label_for(node_name)
        node = node_name.to_s
        LABELS[node] || "処理中（#{node}）…"
      end

      def model_name_for(node_name, chat)
        return nil unless LLM_NODES.include?(node_name.to_s)

        if node_name.to_s == "draft_memo"
          draft = AppSetting.research_draft_model
          if draft
            return draft.name.presence || draft.model_id
          end
        end

        chat.model_association&.name.presence || chat.model_association&.model_id
      end

      def broadcast(chat, label:, model_name: nil, node_name: nil, node_started_at: nil, run_started_at: nil)
        ChatChannel.broadcast_to(chat, {
          type: "agent_run_progress",
          label: label,
          model_name: model_name,
          node_name: node_name,
          node_started_at: node_started_at,
          run_started_at: run_started_at,
          html: render_panel(
            label: label,
            model_name: model_name,
            node_started_at: node_started_at,
            run_started_at: run_started_at
          )
        }.compact)
      end

      def render_panel(label:, model_name: nil, node_started_at: nil, run_started_at: nil)
        return "" if label.blank?

        ApplicationController.render(
          partial: "chats/agent_run_progress",
          locals: {
            label: label,
            model_name: model_name,
            node_started_at: node_started_at,
            run_started_at: run_started_at
          }
        )
      end

      def node_started_at_for(agent_run)
        agent_run.agent_node_runs
          .where(status: "running", node_name: agent_run.current_node)
          .order(started_at: :desc, id: :desc)
          .pick(:started_at) || agent_run.updated_at || agent_run.started_at
      end
    end
  end
end
