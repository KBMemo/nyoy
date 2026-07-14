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

      private

      def broadcast(chat, html)
        ChatChannel.broadcast_to(chat, {
          type: "approval_panel",
          html: html
        })
      end

      def render_panel(agent_run)
        ApplicationController.render(
          partial: "chats/research_approval",
          locals: { chat: agent_run.chat, agent_run: agent_run }
        )
      end
    end
  end
end
