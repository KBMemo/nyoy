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
    backfill_assignments!
    guard_migrated_values!
    COLUMNS.each_key { |column| remove_column :app_settings, column }
  end

  def down
    COLUMNS.each_key { |column| add_column :app_settings, column, :string }
  end

  private

  def backfill_assignments!
    setting = select_one(<<~SQL.squish)
      SELECT #{COLUMNS.keys.map { |column| quote_column_name(column) }.join(', ')}
      FROM app_settings ORDER BY id LIMIT 1
    SQL
    return unless setting

    chat_model_id = model_id_for_connection(setting["default_chat_connection_key"])
    preset_id = sampling_preset_id_for(setting["default_llm_sampling_preset_key"])
    insert_assignment("chat.default", chat_model_id, sampling_preset_id: preset_id)

    COLUMNS.except(
      :default_chat_connection_key,
      :default_llm_sampling_preset_key,
      :default_style_plan_connection_key
    ).each do |column, usage_key|
      insert_assignment(usage_key, model_id_for_alias(setting[column.to_s]) || chat_model_id)
    end

    style_model_id = model_id_for_connection(setting["default_style_plan_connection_key"])
    insert_assignment("image.style_plan", style_model_id || chat_model_id)
  end

  def model_id_for_connection(connection_key)
    return if connection_key.blank?

    select_value(<<~SQL.squish)
      SELECT id FROM models
      WHERE metadata ->> 'connection_key' = #{quote(connection_key)}
      ORDER BY id LIMIT 1
    SQL
  end

  def model_id_for_alias(model_id)
    return if model_id.blank?

    select_value(<<~SQL.squish)
      SELECT id FROM models WHERE model_id = #{quote(model_id)} ORDER BY id LIMIT 1
    SQL
  end

  def sampling_preset_id_for(key)
    return if key.blank?

    select_value("SELECT id FROM llm_sampling_presets WHERE key = #{quote(key)} LIMIT 1")
  end

  def insert_assignment(usage_key, model_id, sampling_preset_id: nil)
    return if model_id.blank?

    now = quote(Time.current)
    sampling_preset_sql = sampling_preset_id.present? ? quote(sampling_preset_id) : "NULL"
    execute <<~SQL.squish
      INSERT INTO llm_usage_assignments
        (usage_key, model_id, llm_sampling_preset_id, enabled, created_at, updated_at)
      VALUES
        (#{quote(usage_key)}, #{quote(model_id)}, #{sampling_preset_sql}, TRUE, #{now}, #{now})
      ON CONFLICT (usage_key) DO NOTHING
    SQL
  end

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
