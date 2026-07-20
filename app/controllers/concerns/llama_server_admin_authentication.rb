# frozen_string_literal: true

module LlamaServerAdminAuthentication
  extend ActiveSupport::Concern

  SESSION_KEY = :llama_server_admin

  included do
    helper_method :llama_server_admin_authenticated?
  end

  private

  def require_llama_server_admin!
    return if llama_server_admin_authenticated?

    session[:llama_server_admin_return_to] = request.fullpath if request.get?
    redirect_to new_llama_server_admin_session_path, alert: "LLMサーバー管理の認証が必要です。"
  end

  def llama_server_admin_authenticated?
    expected = llama_server_admin_token
    authentication = session[SESSION_KEY]
    return false if expected.blank? || !authentication.is_a?(Hash)

    authenticated_at = Time.zone.at(authentication["authenticated_at"].to_i)
    return false if authenticated_at < llama_server_admin_session_ttl.ago

    ActiveSupport::SecurityUtils.secure_compare(
      authentication["token_digest"].to_s,
      Digest::SHA256.hexdigest(expected)
    )
  end

  def authenticate_llama_server_admin!(token)
    expected = llama_server_admin_token
    return false if expected.blank? || token.blank?
    return false unless ActiveSupport::SecurityUtils.secure_compare(token, expected)

    session[SESSION_KEY] = {
      "authenticated_at" => Time.current.to_i,
      "token_digest" => Digest::SHA256.hexdigest(expected)
    }
    true
  end

  def llama_server_admin_token
    Rails.application.config.x.nyoy.llama_server_admin_token.to_s
  end

  def llama_server_admin_session_ttl
    Rails.application.config.x.nyoy.llama_server_admin_session_ttl
  end
end
