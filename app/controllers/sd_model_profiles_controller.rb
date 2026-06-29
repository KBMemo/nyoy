# frozen_string_literal: true

class SdModelProfilesController < ApplicationController
  before_action :set_sd_model_profile, only: %i[show edit update destroy]

  def index
    @sd_model_profiles = SdModelProfile.ordered
  end

  def show
  end

  def new
    @sd_model_profile = SdModelProfile.new(enabled: true, sort_order: SdModelProfile.maximum(:sort_order).to_i + 1)
  end

  def create
    @sd_model_profile = SdModelProfile.new(sd_model_profile_params)

    if @sd_model_profile.save
      redirect_to @sd_model_profile, notice: "モデルプロファイルを登録しました。"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @sd_model_profile.update(sd_model_profile_params)
      redirect_to @sd_model_profile, notice: "モデルプロファイルを更新しました。"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @sd_model_profile.destroy
      redirect_to sd_model_profiles_path, notice: "モデルプロファイルを削除しました。"
    else
      redirect_to @sd_model_profile, alert: "スタイルに紐づいているため削除できません。"
    end
  end

  private

  def set_sd_model_profile
    @sd_model_profile = SdModelProfile.find(params[:id])
  end

  def sd_model_profile_params
    permitted = params.require(:sd_model_profile).permit(
      :key,
      :name,
      :family,
      :switch_key,
      :base_url,
      :default_params_json,
      :notes,
      :enabled,
      :sort_order
    )
    permitted.delete(:key) if @sd_model_profile&.linked_to_styles?
    permitted
  end
end
