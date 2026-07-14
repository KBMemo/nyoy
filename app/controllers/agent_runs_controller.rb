# frozen_string_literal: true

class AgentRunsController < ApplicationController
  before_action :set_chat
  before_action :set_agent_run

  def approve
    resume!("approved", notice: "調査ドラフトを承認しました。回答を確定します。")
  end

  def reject
    resume!("rejected", notice: "調査ドラフトを却下しました。")
  end

  private

  def set_chat
    @chat = Chat.find(params[:chat_id])
  end

  def set_agent_run
    @agent_run = @chat.agent_runs.find(params[:id])
  end

  def resume!(decision, notice:)
    unless @agent_run.awaiting_approval?
      redirect_to @chat, alert: "承認待ちの調査実行ではありません。"
      return
    end

    if @chat.responding?
      redirect_to @chat, alert: "別の応答が実行中です。"
      return
    end

    ChatResponseControl.mark_running!(@chat)
    AgentGraphResumeJob.perform_later(@agent_run.id, decision)
    redirect_to @chat, notice: notice
  end
end
