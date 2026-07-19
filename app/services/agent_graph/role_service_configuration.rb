# frozen_string_literal: true

module AgentGraph
  module RoleServiceConfiguration
    module_function

    def profile_for(role)
      key = role.to_s
      stored = AppSetting.first&.agent_graph_role_profiles.to_h[key].to_s.presence
      configured = Rails.application.config.x.nyoy.agent_graph_role_profiles.to_h[key].to_s.presence
      (stored || configured)&.to_sym
    end
  end
end
