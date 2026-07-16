# frozen_string_literal: true

class AgentGraphResumeJob < ApplicationJob
  def perform(agent_run_id, decision)
    run = AgentRun.find(agent_run_id)
    chat = run.chat

    if chat.response_state == ChatResponseControl::STATES[:cancelled]
      ChatCancellationBroadcaster.call(chat)
      return
    end

    # Controller may already have written approval; resume is idempotent on that.
    completed = resume_runner(run, decision)
    if completed.failed?
      ChatErrorBroadcaster.fail!(
        chat,
        AgentGraph::Error.new(completed.error_message.presence || failure_label(run))
      )
    end
  rescue ChatResponseControl::Cancelled
    ChatCancellationBroadcaster.call(chat)
  rescue StandardError => e
    Rails.logger.error("AgentGraphResumeJob failed for run=#{agent_run_id}: #{e.full_message}")
    ChatErrorBroadcaster.fail!(chat, e)
  ensure
    ChatResponseControl.finish!(chat) if chat
    ChatUiBroadcaster.form_updated(chat) if chat
  end

  private

  def resume_runner(run, decision)
    case run.graph_name.to_s
    when AgentGraph::MemoWriteGraph::NAME
      AgentGraph::MemoWriteGraphRunner.resume(run, decision: decision)
    when AgentGraph::MemoUpdateGraph::NAME
      AgentGraph::MemoUpdateGraphRunner.resume(run, decision: decision)
    else
      raise ArgumentError, "approval resume is not supported for graph=#{run.graph_name}"
    end
  end

  def failure_label(run)
    case run.graph_name.to_s
    when AgentGraph::MemoWriteGraph::NAME
      "MemoWrite Graph failed"
    when AgentGraph::MemoUpdateGraph::NAME
      "MemoUpdate Graph failed"
    else
      "#{run.graph_name} Graph failed"
    end
  end
end
