# frozen_string_literal: true

class AgentGraphResumeJob < ApplicationJob
  def perform(agent_run_id, decision)
    run = AgentRun.find(agent_run_id)
    chat = run.chat

    if chat.response_state == ChatResponseControl::STATES[:cancelled]
      ChatCancellationBroadcaster.call(chat)
      return
    end

    AgentGraph::ResearchGraphRunner.resume(run, decision: decision)
  rescue ChatResponseControl::Cancelled
    ChatCancellationBroadcaster.call(chat)
  rescue StandardError => e
    Rails.logger.error("AgentGraphResumeJob failed for run=#{agent_run_id}: #{e.full_message}")
    ChatErrorBroadcaster.fail!(chat, e)
  ensure
    ChatResponseControl.finish!(chat) if chat
    ChatUiBroadcaster.form_updated(chat) if chat
  end
end
