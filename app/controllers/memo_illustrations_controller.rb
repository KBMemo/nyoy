# frozen_string_literal: true

class MemoIllustrationsController < ApplicationController
  include SdCatalogLoadable

  before_action :set_memo_illustration, only: :show
  before_action :load_sd_catalog, only: %i[index new create]
  before_action :load_prompt_skills, only: %i[new create]

  def index
    @memo_illustrations = MemoIllustration.recent.limit(20)
  end

  def show
  end

  def new
    @memo_illustration = MemoIllustration.new
  end

  def create
    if @catalog_error.present?
      redirect_to new_memo_illustration_path, alert: "SD モデル一覧を取得できないため生成できません。"
      return
    end

    sd_model = resolve_sd_model
    if sd_model.blank?
      redirect_to new_memo_illustration_path, alert: "利用可能な SD モデルがありません。"
      return
    end

    skill = PromptSkill.find_by(id: memo_illustration_params[:prompt_skill_id]) ||
            PromptSkill.default_for_generation

    unless skill
      redirect_to prompt_skills_path, alert: "先にプロンプトスキルを作成してください。"
      return
    end

    unless skill.json_plan?
      @memo_illustration = MemoIllustration.new(memo_illustration_params)
      @memo_illustration.errors.add(:prompt_skill_id, "メモイラストには JSON 出力スキルを選んでください")
      render :new, status: :unprocessable_entity
      return
    end

    @memo_illustration = MemoIllustration.new(
      body: memo_illustration_params[:body],
      prompt_skill: skill,
      sd_model: sd_model
    )

    if @memo_illustration.save
      GenerateMemoIllustrationJob.perform_later(@memo_illustration.id)
      redirect_to @memo_illustration
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def set_memo_illustration
    @memo_illustration = MemoIllustration.find(params[:id])
  end

  def load_prompt_skills
    @prompt_skills = PromptSkill.json_plan.ordered
  end

  def memo_illustration_params
    params.require(:memo_illustration).permit(:body, :prompt_skill_id)
  end
end
