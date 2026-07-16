# frozen_string_literal: true

class AgentGraphRetryJob < ApplicationJob
  def perform(agent_run_id)
    run = AgentRun.find(agent_run_id)
    chat = run.chat

    if chat.response_state == ChatResponseControl::STATES[:cancelled]
      ChatCancellationBroadcaster.call(chat)
      return
    end

    retry_run = AgentGraph::RunRetryLauncher.call(run)
    if retry_run.failed?
      ChatErrorBroadcaster.fail!(
        chat,
        AgentGraph::Error.new(retry_run.error_message.presence || failure_label(retry_run))
      )
    end
  rescue ChatResponseControl::Cancelled
    ChatCancellationBroadcaster.call(chat)
  rescue StandardError => e
    Rails.logger.error("AgentGraphRetryJob failed for run=#{agent_run_id}: #{e.full_message}")
    ChatErrorBroadcaster.fail!(chat, e)
  ensure
    ChatResponseControl.finish!(chat) if chat
    ChatUiBroadcaster.form_updated(chat) if chat
  end

  private

  def failure_label(run)
    AgentGraph::Registry.failure_label_for(run.graph_name)
  end
end
