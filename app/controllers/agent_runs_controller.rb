# frozen_string_literal: true

class AgentRunsController < ApplicationController
  before_action :set_chat
  before_action :set_agent_run

  def show
    @node_runs = @agent_run.agent_node_runs.order(:id)
    @checkpoints = @agent_run.agent_checkpoints.order(:id)
    @failed_node_run = @agent_run.failed_node_run
    @latest_checkpoint = @agent_run.latest_checkpoint
    @recovery_candidates = @agent_run.recovery_candidates
  end

  def approve
    resume!("approved")
  end

  def reject
    resume!("rejected")
  end

  private

  def set_chat
    @chat = Chat.find(params[:chat_id])
  end

  def set_agent_run
    @agent_run = @chat.agent_runs.find(params[:id])
  end

  def approve_notice
    AgentGraph::Registry.approve_notice_for(@agent_run.graph_name)
  end

  def reject_notice
    AgentGraph::Registry.reject_notice_for(@agent_run.graph_name)
  end

  def resume!(decision)
    unless AgentGraph::Registry.approval_supported?(@agent_run.graph_name)
      return resume_blocked!("この Graph は承認再開に対応していません。")
    end

    unless @agent_run.awaiting_approval?
      return resume_blocked!("承認待ちの実行ではありません。")
    end

    if @agent_run.state["approval"].to_s.in?(%w[approved rejected])
      return resume_blocked!("このドラフトはすでに処理中です。")
    end

    if @chat.responding?
      return resume_blocked!("別の応答が実行中です。")
    end

    # Persist the decision before the async job. Turbo replaces the panel with a
    # short status; finalize clears it after the answer is upserted.
    @agent_run.merge_state!("approval" => decision)
    ChatResponseControl.mark_running!(@chat)
    AgentGraphResumeJob.perform_later(@agent_run.id, decision)
    @notice = decision == "approved" ? approve_notice : reject_notice

    respond_to do |format|
      # Keep the page/Cable subscription alive so finalize + truncation broadcasts
      # are not lost during a Turbo Drive redirect gap.
      format.turbo_stream { render :resume }
      format.html { redirect_to @chat, notice: @notice }
    end
  end

  def resume_blocked!(alert)
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.update("agent_run_approval", html: %(<div class="kb-alert kb-alert-danger" role="alert">#{ERB::Util.html_escape(alert)}</div>)),
               status: :unprocessable_entity
      end
      format.html { redirect_to @chat, alert: alert }
    end
  end
end
