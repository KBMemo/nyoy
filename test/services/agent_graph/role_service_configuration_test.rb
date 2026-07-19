# frozen_string_literal: true

require "test_helper"

class AgentGraphRoleServiceConfigurationTest < ActiveSupport::TestCase
  setup do
    AppSetting.delete_all
    @original_profiles = Rails.application.config.x.nyoy.agent_graph_role_profiles
    Rails.application.config.x.nyoy.agent_graph_role_profiles = {}
    AgentGraph::RoleServices.reset!
  end

  teardown do
    Rails.application.config.x.nyoy.agent_graph_role_profiles = @original_profiles
    AgentGraph::RoleServices.reset!
    AppSetting.delete_all
  end

  test "uses the built in profile when no configuration exists" do
    assert_equal :evidence_pack, AgentGraph::RoleServices.profile_for(:draft)
  end

  test "uses environment-backed Rails configuration" do
    Rails.application.config.x.nyoy.agent_graph_role_profiles = { "draft" => "llm" }

    assert_equal :llm, AgentGraph::RoleServices.profile_for(:draft)
    assert_instance_of AgentGraph::RoleServices::LlmDraft, AgentGraph::RoleServices.fetch(:draft)
  end

  test "stored AppSetting profile takes precedence over environment configuration" do
    Rails.application.config.x.nyoy.agent_graph_role_profiles = { "draft" => "evidence_pack" }
    AppSetting.create!(agent_graph_role_profiles: { "draft" => "llm" })

    assert_equal :llm, AgentGraph::RoleServices.profile_for(:draft)
  end

  test "explicit runtime selection takes precedence over stored profile" do
    AppSetting.create!(agent_graph_role_profiles: { "draft" => "llm" })
    AgentGraph::RoleServices.select_profile(:draft, :evidence_pack)

    assert_equal :evidence_pack, AgentGraph::RoleServices.profile_for(:draft)
  end

  test "configured unknown profile fails explicitly when fetched" do
    AppSetting.create!(agent_graph_role_profiles: { "draft" => "missing" })

    error = assert_raises(KeyError) { AgentGraph::RoleServices.fetch(:draft) }
    assert_includes error.message, "unknown AgentGraph role service profile: draft.missing"
  end
end
