# frozen_string_literal: true

class PromptPresetsController < ApplicationController
  before_action :set_prompt_preset, only: %i[show edit update destroy]

  def index
    @prompt_presets = PromptPreset.ordered
  end

  def show
  end

  def new
    @prompt_preset = PromptPreset.new(model_family: "pony", default_params: {})
  end

  def create
    @prompt_preset = PromptPreset.new(prompt_preset_params)

    if @prompt_preset.save
      redirect_to @prompt_preset, notice: "プロンプトプリセットを登録しました。"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if params[:save_as].present?
      save_as_duplicate
    elsif @prompt_preset.update(prompt_preset_params)
      redirect_to @prompt_preset, notice: "プロンプトプリセットを更新しました。"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @prompt_preset.destroy!
    redirect_to prompt_presets_path, notice: "プロンプトプリセットを削除しました。"
  end

  private

  def set_prompt_preset
    @prompt_preset = PromptPreset.find(params[:id])
  end

  def prompt_preset_params
    params.require(:prompt_preset).permit(
      :name,
      :model_family,
      :positive_template,
      :negative_template,
      :default_params_json
    )
  end

  def save_as_duplicate
    duplicate = @prompt_preset.duplicate_with(prompt_preset_params.to_h)

    if duplicate.save
      redirect_to duplicate, notice: "別名で保存しました: #{duplicate.name}"
    else
      @prompt_preset.assign_attributes(prompt_preset_params)
      duplicate.errors.full_messages.each do |message|
        @prompt_preset.errors.add(:base, message)
      end
      render :edit, status: :unprocessable_entity
    end
  end
end
