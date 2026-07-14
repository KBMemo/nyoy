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
    ChatModelCatalog.seed! if ServiceConnection.chat_backends.enabled.any?
    @app_setting = AppSetting.instance
    @connection_options = StylePlanModelCatalog.options_for_select
    @llm_sampling_presets = LlmSamplingPreset.enabled.ordered
    @research_draft_model_options = research_draft_model_options
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
      :research_draft_model_id,
      :research_draft_fallback
    ).to_h.transform_values { |value| value.to_s.presence }

    attrs["research_draft_fallback"] ||= "main"
    attrs
  end
end
