# frozen_string_literal: true

class AgentRunsController < ApplicationController
  before_action :set_chat
  before_action :set_agent_run

  def approve
    resume!("approved", notice: approve_notice)
  end

  def reject
    resume!("rejected", notice: reject_notice)
  end

  private

  def set_chat
    @chat = Chat.find(params[:chat_id])
  end

  def set_agent_run
    @agent_run = @chat.agent_runs.find(params[:id])
  end

  def approve_notice
    case @agent_run.graph_name
    when AgentGraph::MemoWriteGraph::NAME
      "メモ草案を承認しました。徒然へ保存します。"
    else
      "調査ドラフトを承認しました。回答を確定します。"
    end
  end

  def reject_notice
    case @agent_run.graph_name
    when AgentGraph::MemoWriteGraph::NAME
      "メモ保存を却下しました。"
    else
      remaining = [
        AgentGraph::Nodes::AwaitApproval::MAX_REPLANS - @agent_run.state["replan_count"].to_i,
        0
      ].max
      if remaining.positive?
        "調査ドラフトを却下しました。調査をやり直します。"
      else
        "調査ドラフトを却下しました。"
      end
    end
  end

  def resume!(decision, notice:)
    unless @agent_run.awaiting_approval?
      redirect_to @chat, alert: "承認待ちの実行ではありません。"
      return
    end

    if @agent_run.state["approval"].to_s.in?(%w[approved rejected])
      redirect_to @chat, alert: "このドラフトはすでに処理中です。"
      return
    end

    if @chat.responding?
      redirect_to @chat, alert: "別の応答が実行中です。"
      return
    end

    # Persist the decision and clear the panel before the async job so a
    # redirect to show does not re-render the stale approval UI.
    @agent_run.merge_state!("approval" => decision)
    AgentGraph::ApprovalBroadcaster.clear!(@chat)
    ChatResponseControl.mark_running!(@chat)
    AgentGraphResumeJob.perform_later(@agent_run.id, decision)
    redirect_to @chat, notice: notice
  end
end
