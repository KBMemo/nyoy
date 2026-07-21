# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/migrate/20260721070000_remove_legacy_llm_settings_from_app_settings")

class RemoveLegacyLlmSettingsFromAppSettingsTest < ActiveSupport::TestCase
  test "backfills usage assignments before removing legacy settings" do
    migration = RemoveLegacyLlmSettingsFromAppSettings.new
    inserted = []
    setting = {
      "default_chat_connection_key" => "chat-connection",
      "default_style_plan_connection_key" => "style-connection",
      "default_llm_sampling_preset_key" => "sampling-key",
      "agent_graph_intent_model_id" => "intent-model",
      "research_planner_model_id" => nil,
      "evidence_evaluator_model_id" => nil,
      "research_draft_model_id" => nil,
      "final_answer_model_id" => nil
    }
    migration.define_singleton_method(:select_one) { |_| setting }
    migration.define_singleton_method(:model_id_for_connection) do |key|
      { "chat-connection" => 10, "style-connection" => 20 }[key]
    end
    migration.define_singleton_method(:model_id_for_alias) { |model_id| model_id == "intent-model" ? 30 : nil }
    migration.define_singleton_method(:sampling_preset_id_for) { |key| key == "sampling-key" ? 40 : nil }
    migration.define_singleton_method(:insert_assignment) do |usage_key, model_id, sampling_preset_id: nil|
      inserted << [ usage_key, model_id, sampling_preset_id ]
    end

    migration.send(:backfill_assignments!)

    assert_includes inserted, [ "chat.default", 10, 40 ]
    assert_includes inserted, [ "image.style_plan", 20, nil ]
    assert_includes inserted, [ "agent.intent", 30, nil ]
    assert_includes inserted, [ "agent.planner", 10, nil ]
    assert_equal 7, inserted.size
  end

  test "writes SQL NULL when a sampling preset is absent" do
    migration = RemoveLegacyLlmSettingsFromAppSettings.new
    statements = []
    migration.define_singleton_method(:execute) { |sql| statements << sql }

    migration.send(:insert_assignment, "chat.default", 10)

    assert_match(/'chat\.default', '10', NULL, TRUE/, statements.fetch(0))
  end
end
