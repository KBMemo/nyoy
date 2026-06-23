# frozen_string_literal: true

class MemoIllustrationsController < ApplicationController
  before_action :set_memo_illustration, only: :show
  before_action :load_catalog, only: %i[index new create]
  before_action :load_prompt_skills, only: %i[new create]

  def index
    @memo_illustrations = MemoIllustration.recent.limit(20)
    @current_sd_model = @catalog.current_model
  end

  def show
  end

  def new
    @memo_illustration = MemoIllustration.new
  end

  def create
    skill = PromptSkill.find_by(id: memo_illustration_params[:prompt_skill_id]) ||
            PromptSkill.default_for_generation

    unless skill
      redirect_to prompt_skills_path, alert: "先にプロンプトスキルを作成してください。"
      return
    end

    @memo_illustration = MemoIllustration.new(
      body: memo_illustration_params[:body],
      prompt_skill: skill,
      sd_model: resolve_sd_model
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

  def load_catalog
    @catalog = SdModelCatalog.new
  end

  def load_prompt_skills
    @prompt_skills = PromptSkill.ordered
  end

  def resolve_sd_model
    @catalog.current_model.presence ||
      Rails.application.config.x.nyoy.default_sd_models.first ||
      "flat2d"
  end

  def memo_illustration_params
    params.require(:memo_illustration).permit(:body, :prompt_skill_id)
  end
end
