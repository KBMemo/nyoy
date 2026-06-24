# frozen_string_literal: true

class PromptSkillsController < ApplicationController
  before_action :set_prompt_skill, only: %i[show edit update destroy]

  def index
    @prompt_skills = PromptSkill.ordered
  end

  def show
  end

  def new
    @prompt_skill = PromptSkill.new(default: PromptSkill.none?)
  end

  def create
    @prompt_skill = PromptSkill.new(prompt_skill_params)

    if @prompt_skill.save
      redirect_to @prompt_skill, notice: "スキルを作成しました。"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @prompt_skill.update(prompt_skill_params)
      redirect_to @prompt_skill, notice: "スキルを更新しました。"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @prompt_skill.memo_illustrations.exists?
      redirect_to @prompt_skill, alert: "このスキルを使った生成履歴があるため削除できません。"
      return
    end

    @prompt_skill.destroy!
    redirect_to prompt_skills_path, notice: "スキルを削除しました。"
  end

  private

  def set_prompt_skill
    @prompt_skill = PromptSkill.find(params[:id])
  end

  def prompt_skill_params
    params.require(:prompt_skill).permit(:name, :body, :default, :default_negative_prompt)
  end
end
