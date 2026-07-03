# frozen_string_literal: true

class MemoIllustrationsController < ApplicationController
  before_action :set_memo_illustration, only: %i[show destroy inpaint create_inpaint translate_inpaint_note destroy_inpainted_image progress]
  before_action :set_inpainted_attachment, only: %i[destroy_inpainted_image]
  before_action :load_prompt_styles, only: %i[new create]
  before_action :recover_stale_inpaint_status!, only: %i[show inpaint]
  before_action :ensure_inpaint_page_accessible!, only: %i[inpaint]
  before_action :ensure_inpaintable!, only: %i[create_inpaint]
  before_action :reject_inpaint_while_running!, only: %i[create_inpaint]

  def index
    @memo_illustrations = MemoIllustration.recent.limit(20)
  end

  def show
  end

  def inpaint
    @source_attachment = resolve_inpaint_source(params[:source_attachment_id])
    @prompt_style = @memo_illustration.prompt_style
  end

  def create_inpaint
    mask_data = params[:mask].to_s
    if mask_data.blank?
      redirect_to inpaint_memo_illustration_path(@memo_illustration), alert: "修正したい範囲をマスクしてください"
      return
    end

    @memo_illustration.update!(
      status: "inpainting",
      image_started_at: Time.current,
      image_finished_at: nil,
      error_message: nil
    )

    InpaintMemoIllustrationJob.perform_later(
      @memo_illustration.id,
      mask_data: mask_data,
      inpaint_note: params[:inpaint_note],
      inpaint_prompt_delta: params[:inpaint_prompt_delta],
      include_style_prefix: params[:include_style_prefix] == "1",
      include_style_suffix: params[:include_style_suffix] == "1",
      denoising_strength: params[:denoising_strength],
      source_attachment_id: params[:source_attachment_id]
    )

    redirect_to inpaint_memo_illustration_path(
      @memo_illustration,
      source_attachment_id: params[:source_attachment_id],
      submitted: 1
    )
  end

  def progress
    render json: {
      status: @memo_illustration.status,
      finished: @memo_illustration.finished?
    }
  end

  def translate_inpaint_note
    note = params[:inpaint_note].to_s.strip
    if note.blank?
      return render json: { error: "修正指示を入力してください" }, status: :unprocessable_entity
    end

    if InpaintNoteTranslator.japanese?(note)
      translated = InpaintNoteTranslator.new.translate(note)
      render json: { inpaint_note: note, translated_note: translated, translated: true }
    else
      render json: { inpaint_note: note, translated_note: note, translated: false }
    end
  rescue InpaintNoteTranslator::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy
    if @memo_illustration.in_progress?
      redirect_to memo_illustrations_path, alert: "生成中のイラストは削除できません"
      return
    end

    @memo_illustration.destroy!
    redirect_to memo_illustrations_path, notice: "イラストを削除しました"
  end

  def destroy_inpainted_image
    if @memo_illustration.in_progress?
      redirect_to @memo_illustration, alert: "生成中は修正版を削除できません"
      return
    end

    label = @memo_illustration.inpainted_image_label(@inpainted_attachment)
    @inpainted_attachment.purge
    redirect_to @memo_illustration, notice: "#{label} を削除しました"
  end

  def new
    @memo_illustration = build_new_memo_illustration
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

  def set_inpainted_attachment
    @inpainted_attachment = @memo_illustration.inpainted_images.attachments.find_by(id: params[:attachment_id])
    return if @inpainted_attachment

    redirect_to @memo_illustration, alert: "修正版が見つかりません"
  end

  def load_prompt_styles
    @prompt_styles = PromptStyle.enabled.ordered
    load_style_plan_connection_options
  end

  def memo_illustration_params
    params.require(:memo_illustration).permit(:body, :style_id, :style_plan_connection_key)
  end

  def build_new_memo_illustration
    illustration = MemoIllustration.new

    if params[:copy_from].present?
      source = MemoIllustration.find_by(id: params[:copy_from])
      source&.apply_form_settings_to(illustration)
    end

    illustration
  end

  def ensure_inpaintable!
    return if @memo_illustration.inpaintable?

    redirect_to @memo_illustration, alert: "このイラストは部分修正できません"
  end

  def ensure_inpaint_page_accessible!
    return if @memo_illustration.inpaintable?
    return if @memo_illustration.status == "inpainting"

    redirect_to @memo_illustration, alert: "このイラストは部分修正できません"
  end

  def reject_inpaint_while_running!
    return unless @memo_illustration.status == "inpainting"

    redirect_to inpaint_memo_illustration_path(
      @memo_illustration,
      source_attachment_id: params[:source_attachment_id],
      submitted: 1
    ), alert: "部分修正中です"
  end

  def recover_stale_inpaint_status!
    @memo_illustration.recover_stale_inpaint!(submitted: params[:submitted] == "1")
    @memo_illustration.reload if @memo_illustration.previous_changes.any?
  end

  def resolve_inpaint_source(attachment_id)
    if attachment_id.present?
      attachment = @memo_illustration.inpainted_images.attachments.find_by(id: attachment_id)
      return attachment if attachment

      if @memo_illustration.image_attachment&.id == attachment_id.to_i
        return @memo_illustration.image_attachment
      end
    end

    @memo_illustration.default_inpaint_source_attachment
  end
end
