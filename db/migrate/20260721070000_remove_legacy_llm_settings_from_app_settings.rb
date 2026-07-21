# frozen_string_literal: true

class RemoveLegacyLlmSettingsFromAppSettings < ActiveRecord::Migration[8.1]
  COLUMNS = {
    agent_graph_intent_model_id: "agent.intent",
    default_chat_connection_key: "chat.default",
    default_llm_sampling_preset_key: "chat.default",
    default_style_plan_connection_key: "image.style_plan",
    evidence_evaluator_model_id: "agent.evidence_evaluator",
    final_answer_model_id: "agent.final_answer",
    research_draft_model_id: "agent.draft",
    research_planner_model_id: "agent.planner"
  }.freeze

  def up
    guard_migrated_values!
    COLUMNS.each_key { |column| remove_column :app_settings, column }
  end

  def down
    COLUMNS.each_key { |column| add_column :app_settings, column, :string }
  end

  private

  def guard_migrated_values!
    COLUMNS.each do |column, usage_key|
      next unless legacy_value_exists?(column)
      next if assignment_exists?(usage_key)

      raise ActiveRecord::MigrationError,
            "app_settings.#{column} has a value but #{usage_key} has no LLM usage assignment"
    end
  end

  def legacy_value_exists?(column)
    select_value(<<~SQL.squish).to_i.positive?
      SELECT COUNT(*) FROM app_settings
      WHERE #{quote_column_name(column)} IS NOT NULL
        AND #{quote_column_name(column)} <> ''
    SQL
  end

  def assignment_exists?(usage_key)
    select_value(<<~SQL.squish).to_i.positive?
      SELECT COUNT(*) FROM llm_usage_assignments
      WHERE usage_key = #{quote(usage_key)}
    SQL
  end
end
