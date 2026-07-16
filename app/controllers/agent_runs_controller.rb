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
    "メモ草案を承認しました。徒然へ保存します。"
  end

  def reject_notice
    "メモ保存を却下しました。"
  end

  def resume!(decision, notice:)
    unless @agent_run.graph_name == AgentGraph::MemoWriteGraph::NAME
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
    @notice = notice

    respond_to do |format|
      # Keep the page/Cable subscription alive so finalize + truncation broadcasts
      # are not lost during a Turbo Drive redirect gap.
      format.turbo_stream { render :resume }
      format.html { redirect_to @chat, notice: notice }
    end
  end

  def resume_blocked!(alert)
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.update("research_approval", html: %(<div class="kb-alert kb-alert-danger" role="alert">#{ERB::Util.html_escape(alert)}</div>)),
               status: :unprocessable_entity
      end
      format.html { redirect_to @chat, alert: alert }
    end
  end
end
