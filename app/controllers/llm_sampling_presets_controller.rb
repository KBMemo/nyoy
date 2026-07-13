# frozen_string_literal: true

class LlmSamplingPresetsController < ApplicationController
  before_action :set_llm_sampling_preset, only: %i[show edit update destroy]

  def index
    @llm_sampling_presets = LlmSamplingPreset.ordered

    respond_to do |format|
      format.html
      format.json do
        render json: {
          presets: LlmSamplingPreset.enabled.ordered.map(&:as_api_json)
        }
      end
    end
  end

  def show
    respond_to do |format|
      format.html
      format.json { render json: @llm_sampling_preset.as_api_json }
    end
  end

  def new
    @llm_sampling_preset = LlmSamplingPreset.new(
      enabled: true,
      builtin: false,
      sort_order: LlmSamplingPreset.maximum(:sort_order).to_i + 10,
      params: {}
    )
  end

  def create
    @llm_sampling_preset = LlmSamplingPreset.new(llm_sampling_preset_params)
    @llm_sampling_preset.builtin = false

    if @llm_sampling_preset.save
      redirect_to @llm_sampling_preset, notice: "サンプリングプリセットを登録しました。"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    attrs = llm_sampling_preset_params
    attrs = attrs.except(:key) if @llm_sampling_preset.builtin?

    if @llm_sampling_preset.update(attrs)
      redirect_to @llm_sampling_preset, notice: "サンプリングプリセットを更新しました。"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @llm_sampling_preset.builtin?
      redirect_to llm_sampling_presets_path, alert: "組み込みプリセットは削除できません。無効化してください。"
      return
    end

    @llm_sampling_preset.destroy!
    redirect_to llm_sampling_presets_path, notice: "サンプリングプリセットを削除しました。"
  end

  private

  def set_llm_sampling_preset
    @llm_sampling_preset = LlmSamplingPreset.find(params[:id])
  end

  def llm_sampling_preset_params
    raw = params.require(:llm_sampling_preset).permit(
      :key,
      :name,
      :notes,
      :model_name_match,
      :enabled,
      :sort_order,
      :enable_thinking,
      *LlmSamplingParams::KEYS
    )
    sampling = LlmSamplingParams.normalize(raw.slice(*LlmSamplingParams::KEYS))
    thinking = raw[:enable_thinking].presence
    sampling["enable_thinking"] =
      case thinking
      when "true" then true
      when "false" then false
      when "unset" then "unset"
      end

    {
      key: raw[:key],
      name: raw[:name],
      notes: raw[:notes],
      model_name_match: raw[:model_name_match],
      enabled: raw[:enabled],
      sort_order: raw[:sort_order],
      params: sampling.compact
    }.compact
  end
end
