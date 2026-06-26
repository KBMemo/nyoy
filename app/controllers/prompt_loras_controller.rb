# frozen_string_literal: true

class PromptLorasController < ApplicationController
  before_action :set_prompt_lora, only: %i[show edit update destroy]

  def index
    @prompt_loras = PromptLora.ordered
  end

  def show
  end

  def new
    @prompt_lora = PromptLora.new(weight_min: 0.5, weight_max: 1.0)
  end

  def create
    @prompt_lora = PromptLora.new(prompt_lora_params)

    if @prompt_lora.save
      redirect_to @prompt_lora, notice: "LoRA 辞書を登録しました。"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @prompt_lora.update(prompt_lora_params)
      redirect_to @prompt_lora, notice: "LoRA 辞書を更新しました。"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @prompt_lora.destroy!
    redirect_to prompt_loras_path, notice: "LoRA 辞書を削除しました。"
  end

  private

  def set_prompt_lora
    @prompt_lora = PromptLora.find(params[:id])
  end

  def prompt_lora_params
    params.require(:prompt_lora).permit(
      :name,
      :path,
      :trigger_words,
      :weight_min,
      :weight_max,
      :notes,
      compatible_models_list: []
    )
  end
end
