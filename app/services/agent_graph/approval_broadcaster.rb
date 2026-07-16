# frozen_string_literal: true

module AgentGraph
  class ApprovalBroadcaster
    class << self
      def request!(agent_run)
        chat = agent_run.chat
        broadcast(chat, render_panel(agent_run))
      end

      def clear!(chat)
        broadcast(chat, "")
      end

      # Shared by Cable and chats#show so refresh uses the same graph-specific UI.
      def panel_partial_for(agent_run)
        Registry.approval_panel_for(agent_run.graph_name)
      end

      private

      def broadcast(chat, html)
        ChatChannel.broadcast_to(chat, {
          type: "approval_panel",
          html: html
        })
      end

      def render_panel(agent_run)
        ApplicationController.render(
          partial: panel_partial_for(agent_run),
          locals: { chat: agent_run.chat, agent_run: agent_run }
        )
      end
    end
  end
end
