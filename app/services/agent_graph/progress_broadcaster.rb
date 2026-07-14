# frozen_string_literal: true

module AgentGraph
  # Thin progress line for Research Graph node execution (Cable → chat UI).
  class ProgressBroadcaster
    LABELS = {
      "plan_research" => "調査計画を作成しています…",
      "recall_memos" => "関連メモを検索しています…",
      "search_web" => "Web を検索しています…",
      "fetch_urls" => "ページを取得しています…",
      "synthesize_draft" => "調査ドラフトを作成しています…",
      "await_approval" => "ドラフトの承認待ちです…",
      "finalize_answer" => "回答を確定しています…"
    }.freeze

    class << self
      def started!(chat, node_name)
        label = LABELS[node_name.to_s] || "調査中（#{node_name}）…"
        broadcast(chat, label)
      end

      def clear!(chat)
        broadcast(chat, nil)
      end

      private

      def broadcast(chat, label)
        ChatChannel.broadcast_to(chat, {
          type: "research_progress",
          label: label,
          html: render_panel(label)
        })
      end

      def render_panel(label)
        return "" if label.blank?

        ApplicationController.render(
          partial: "chats/research_progress",
          locals: { label: label }
        )
      end
    end
  end
end
