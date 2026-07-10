# frozen_string_literal: true

module Mcp
  module_function

  def enabled?
    api_token.present?
  end

  def api_token
    Rails.application.config.x.nyoy.mcp_api_token
  end
end
