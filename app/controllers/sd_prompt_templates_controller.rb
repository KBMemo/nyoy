# frozen_string_literal: true

class SdPromptTemplatesController < ApplicationController
  before_action :set_sd_prompt_template, only: %i[show edit update destroy]
  before_action :load_form_collections, only: %i[new create edit update]

  def index
    @sd_prompt_templates = SdPromptTemplate.includes(:sd_model_profile).ordered
  end

  def show
  end

  def new
    @sd_prompt_template = SdPromptTemplate.new(
      enabled: true,
      sort_order: SdPromptTemplate.maximum(:sort_order).to_i + 1,
      sd_model_profile_id: params[:sd_model_profile_id]
    )
  end

  def create
    @sd_prompt_template = SdPromptTemplate.new(sd_prompt_template_params)

    if @sd_prompt_template.save
      redirect_to @sd_prompt_template, notice: "プロンプト生成テンプレートを登録しました。"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @sd_prompt_template.update(sd_prompt_template_params)
      redirect_to @sd_prompt_template, notice: "プロンプト生成テンプレートを更新しました。"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @sd_prompt_template.destroy!
    redirect_to sd_prompt_templates_path, notice: "プロンプト生成テンプレートを削除しました。"
  end

  private

  def set_sd_prompt_template
    @sd_prompt_template = SdPromptTemplate.find(params[:id])
  end

  def load_form_collections
    @sd_model_profiles = SdModelProfile.ordered
  end

  def sd_prompt_template_params
    params.require(:sd_prompt_template).permit(
      :name,
      :body,
      :family,
      :sd_model_profile_id,
      :enabled,
      :sort_order,
      :notes
    )
  end
end
