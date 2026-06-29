# frozen_string_literal: true

class LoraProfilesController < ApplicationController
  before_action :set_lora_profile, only: %i[show edit update destroy]

  def index
    @lora_profiles = LoraProfile.ordered
  end

  def show
  end

  def new
    @lora_profile = LoraProfile.new(
      enabled: true,
      default_multiplier: 0.7,
      min_multiplier: 0.0,
      max_multiplier: 1.5
    )
  end

  def create
    @lora_profile = LoraProfile.new(lora_profile_params)

    if @lora_profile.save
      redirect_to @lora_profile, notice: "LoRA プロファイルを登録しました。"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @lora_profile.update(lora_profile_params)
      redirect_to @lora_profile, notice: "LoRA プロファイルを更新しました。"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @lora_profile.destroy
      redirect_to lora_profiles_path, notice: "LoRA プロファイルを削除しました。"
    else
      redirect_to @lora_profile, alert: "スタイルに紐づいているため削除できません。"
    end
  end

  private

  def set_lora_profile
    @lora_profile = LoraProfile.find(params[:id])
  end

  def lora_profile_params
    permitted = params.require(:lora_profile).permit(
      :key,
      :name,
      :family,
      :path,
      :trigger_words_text,
      :default_multiplier,
      :min_multiplier,
      :max_multiplier,
      :notes,
      :enabled
    )
    permitted.delete(:key) if @lora_profile&.linked_to_styles?
    permitted
  end
end
