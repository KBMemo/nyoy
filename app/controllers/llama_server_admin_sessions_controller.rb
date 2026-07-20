# frozen_string_literal: true

class LlamaServerAdminSessionsController < ApplicationController
  include LlamaServerAdminAuthentication

  def new
  end

  def create
    if authenticate_llama_server_admin!(params[:token].to_s)
      redirect_to session.delete(:llama_server_admin_return_to).presence || llama_servers_service_connections_path,
        notice: "LLMサーバー管理を認証しました。"
    else
      flash.now[:alert] = llama_server_admin_token.present? ? "管理トークンが一致しません。" : "管理トークンが設定されていません。"
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    session.delete(LlamaServerAdminAuthentication::SESSION_KEY)
    redirect_to root_path, notice: "LLMサーバー管理からログアウトしました。"
  end
end
