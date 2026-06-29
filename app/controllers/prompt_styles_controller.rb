# frozen_string_literal: true

class PromptStylesController < ApplicationController
  before_action :set_prompt_style, only: %i[show edit update destroy]

  def index
    @prompt_styles = PromptStyle.includes(:sd_model_profiles, :lora_profiles).ordered
  end

  def show
  end

  before_action :load_form_options, only: %i[new create edit update]

  def new
    @prompt_style = PromptStyle.new(enabled: true, sort_order: PromptStyle.maximum(:sort_order).to_i + 1)
  end

  def create
    @prompt_style = PromptStyle.new(basic_prompt_style_params)

    if @prompt_style.save
      apply_associations!(@prompt_style)
      if @prompt_style.valid?
        redirect_to @prompt_style, notice: "プロンプトスタイルを登録しました。"
      else
        render :new, status: :unprocessable_entity
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @prompt_style.update(basic_prompt_style_params)
      apply_associations!(@prompt_style)
      if @prompt_style.valid?
        redirect_to @prompt_style, notice: "プロンプトスタイルを更新しました。"
      else
        render :edit, status: :unprocessable_entity
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @prompt_style.referenced?
      redirect_to @prompt_style, alert: "生成履歴またはナレッジから参照されているため削除できません。"
    elsif @prompt_style.destroy
      redirect_to prompt_styles_path, notice: "プロンプトスタイルを削除しました。"
    else
      redirect_to @prompt_style, alert: "削除できませんでした。"
    end
  end

  private

  def set_prompt_style
    @prompt_style = PromptStyle.includes(prompt_style_models: :sd_model_profile,
                                         prompt_style_loras: :lora_profile)
                               .find(params[:id])
  end

  def load_form_options
    @sd_model_profiles = SdModelProfile.enabled.ordered
    @lora_profiles = LoraProfile.enabled.ordered
  end

  def apply_associations!(style)
    sync_models!(style)
    sync_loras!(style)
    style.reload
  end

  def sync_models!(style)
    ids = Array(association_params[:model_profile_ids]).map(&:presence).compact.map(&:to_i)
    default_id = association_params[:default_model_profile_id].to_i

    style.prompt_style_models.where.not(sd_model_profile_id: ids).destroy_all

    ids.each_with_index do |profile_id, index|
      link = style.prompt_style_models.find_or_initialize_by(sd_model_profile_id: profile_id)
      link.assign_attributes(default: profile_id == default_id, sort_order: index)
      link.save!
    end
  end

  def sync_loras!(style)
    ids = Array(association_params[:lora_profile_ids]).map(&:presence).compact.map(&:to_i)
    multipliers = association_params[:lora_multipliers] || {}
    required_flags = association_params[:lora_required] || {}

    style.prompt_style_loras.where.not(lora_profile_id: ids).destroy_all

    ids.each_with_index do |lora_id, index|
      profile = LoraProfile.find(lora_id)
      link = style.prompt_style_loras.find_or_initialize_by(lora_profile_id: lora_id)
      multiplier = multipliers[lora_id.to_s].presence || multipliers[lora_id] || profile.default_multiplier
      link.assign_attributes(
        multiplier: multiplier,
        required: required_flags[lora_id.to_s] == "1" || required_flags[lora_id] == "1",
        sort_order: index
      )
      link.save!
    end
  end

  def basic_prompt_style_params
    permitted = params.require(:prompt_style).permit(
      :style_id,
      :name,
      :description,
      :prompt_prefix,
      :prompt_suffix,
      :negative_prompt,
      :generation_defaults_json,
      :allowed_overrides_json,
      :aspect_presets_json,
      :aliases_text,
      :enabled,
      :sort_order
    )
    permitted.delete(:style_id) if @prompt_style&.referenced?
    permitted
  end

  def association_params
    @association_params ||= params.fetch(:prompt_style, {}).permit(
      :default_model_profile_id,
      model_profile_ids: [],
      lora_profile_ids: [],
      lora_multipliers: {},
      lora_required: {}
    )
  end
end
