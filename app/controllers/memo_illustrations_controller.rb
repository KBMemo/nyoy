# frozen_string_literal: true

class MemoIllustrationsController < ApplicationController
  before_action :set_memo_illustration, only: :show
  before_action :load_prompt_styles, only: %i[new create]

  def index
    @memo_illustrations = MemoIllustration.recent.limit(20)
  end

  def show
  end

  def new
    @memo_illustration = MemoIllustration.new
  end

  def create
    if @prompt_styles.empty?
      redirect_to new_memo_illustration_path, alert: "スタイルが未登録です。先に seed でスタイルを作成してください。"
      return
    end

    @memo_illustration = MemoIllustration.new(memo_illustration_params)

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

  def load_prompt_styles
    @prompt_styles = PromptStyle.enabled.ordered
  end

  def memo_illustration_params
    params.require(:memo_illustration).permit(:body, :style_id)
  end
end
