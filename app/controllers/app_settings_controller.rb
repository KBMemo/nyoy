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
    @app_setting = AppSetting.instance
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

  def app_setting_params
    attrs = params.require(:app_setting).permit(
      :agent_graph_draft_profile,
      :agent_graph_planner_profile,
      :agent_graph_evidence_evaluator_profile,
      :agent_graph_final_answer_profile,
      :agent_graph_intent_profile,
      :research_draft_fallback
    ).to_h.transform_values { |value| value.to_s.presence }

    attrs["research_draft_fallback"] ||= "main"
    attrs
  end
end
