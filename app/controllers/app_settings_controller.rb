# frozen_string_literal: true

class AppSettingsController < ApplicationController
  before_action :load_form

  def edit
  end

  def update
    if @app_setting.update(app_setting_params)
      redirect_to edit_app_settings_path, notice: "既定モデルを更新しました"
    else
      flash.now[:alert] = @app_setting.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def load_form
    ChatModelCatalog.seed! if ServiceConnection.model_endpoints.enabled.any?
    @app_setting = AppSetting.instance
    @connection_options = StylePlanModelCatalog.options_for_select
    @llm_sampling_presets = LlmSamplingPreset.enabled.ordered
    @research_draft_model_options = research_draft_model_options
    @research_planner_model_options = @research_draft_model_options
    @evidence_evaluator_model_options = @research_draft_model_options
    @final_answer_model_options = @research_draft_model_options
    @agent_graph_intent_model_options = @research_draft_model_options
    @agent_graph_intent_profile_options = [
      [ "既定設定", "" ],
      [ "決定規則", "deterministic" ],
      [ "決定規則 + LLM調査判定", "hybrid_llm" ]
    ]
    @research_planner_profile_options = [
      [ "既定設定", "" ],
      [ "決定規則", "deterministic" ],
      [ "LLM分類", "llm" ]
    ]
    @evidence_evaluator_profile_options = [
      [ "既定設定", "" ],
      [ "決定規則", "heuristic" ],
      [ "決定規則 + LLM十分性判定", "llm" ]
    ]
    @final_answer_profile_options = [
      [ "既定設定", "" ],
      [ "チャットのメインモデル", "main" ],
      [ "軽量モデル（失敗時はメイン）", "light" ]
    ]
    @research_draft_profile_options = [
      [ "既定設定", "" ],
      [ "根拠パック", "evidence_pack" ],
      [ "LLM ドラフト", "llm" ]
    ]
    @research_draft_fallback_options = [
      [ "メインモデルで再試行 → だめならテンプレ", "main" ],
      [ "テンプレのみ（メインは使わない）", "template" ]
    ]
  end

  def research_draft_model_options
    ChatModelCatalog.grouped_model_options.map do |group_name, models|
      choices = models.filter_map do |name, record_id|
        model = Model.find_by(id: record_id)
        next unless model

        [ name, model.model_id ]
      end
      [ group_name, choices ]
    end
  end

  def app_setting_params
    attrs = params.require(:app_setting).permit(
      :default_chat_connection_key,
      :default_style_plan_connection_key,
      :default_llm_sampling_preset_key,
      :agent_graph_draft_profile,
      :agent_graph_planner_profile,
      :agent_graph_evidence_evaluator_profile,
      :agent_graph_final_answer_profile,
      :agent_graph_intent_profile,
      :research_draft_model_id,
      :research_planner_model_id,
      :evidence_evaluator_model_id,
      :final_answer_model_id,
      :agent_graph_intent_model_id,
      :research_draft_fallback
    ).to_h.transform_values { |value| value.to_s.presence }

    attrs["research_draft_fallback"] ||= "main"
    attrs
  end
end
