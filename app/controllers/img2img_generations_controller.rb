# frozen_string_literal: true

class Img2imgGenerationsController < ApplicationController
  before_action :set_img2img_generation, only: %i[show destroy]
  before_action :load_generation_options, only: %i[index new create translate_prompt show]

  helper_method :transfer_params

  def index
    @img2img_generations = Img2imgGeneration.recent.limit(20)
  end

  def show
  end

  def destroy
    if @img2img_generation.in_progress?
      redirect_to img2img_generations_path, alert: "生成中の画像は削除できません"
      return
    end

    @img2img_generation.destroy!
    redirect_to img2img_generations_path, notice: "Img2Img 生成を削除しました"
  end

  def new
    @img2img_generation = build_new_img2img_generation
    apply_transfer!(@img2img_generation)
  end

  def create
    @img2img_generation = Img2imgGeneration.new
    apply_transfer_snapshot!(@img2img_generation)
    @img2img_generation.assign_attributes(img2img_generation_params)
    apply_mode_attachments!(@img2img_generation)

    if @img2img_generation.save
      GenerateImg2imgJob.perform_later(@img2img_generation.id)
      redirect_to @img2img_generation
    else
      render :new, status: :unprocessable_entity
    end
  end

  def translate_prompt
    japanese_prompt = params[:japanese_prompt].to_s.strip
    if japanese_prompt.blank?
      return render json: { error: "日本語プロンプトを入力してください" }, status: :unprocessable_entity
    end

    plan = StylePlanGenerator.new(flow: :free).call(
      japanese_prompt,
      forced_style_id: params[:style_id].presence
    )
    aspect_ratio = params[:aspect_ratio].presence || plan.aspect_ratio
    resolved = SdPromptStyleResolver.new(
      style_id: plan.style_id,
      subject_prompt: plan.subject_prompt,
      negative_extra: plan.negative_extra,
      aspect_ratio: aspect_ratio
    ).call

    render json: {
      prompt: resolved[:resolved_prompt],
      negative_prompt: plan.negative_extra
    }
  rescue StylePlanGenerator::Error, SdPromptStyleResolver::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def set_img2img_generation
    @img2img_generation = Img2imgGeneration.find(params[:id])
  end

  def load_generation_options
    @prompt_styles = PromptStyle.enabled.ordered
  end

  def build_new_img2img_generation
    generation = Img2imgGeneration.new(
      width: 768,
      height: 768,
      steps: 22,
      cfg_scale: 6.0,
      sampler_name: "euler_a",
      vae_tiling: true,
      denoising_strength: Img2imgGeneration::DEFAULT_DENOISING_STRENGTH,
      use_source_dimensions: true,
      loras: "[]"
    )

    if params[:copy_from].present?
      source = Img2imgGeneration.find_by(id: params[:copy_from])
      source&.apply_settings_to(generation)
      generation.source_image.attach(source.source_image.blob) if source&.source_image&.attached?
      generation.source_label = source.source_label
    end

    generation
  end

  def apply_transfer!(generation)
    apply_transfer_snapshot!(generation)
  rescue Img2imgSourceTransfer::Error => e
    @transfer_error = e.message
  end

  def apply_transfer_snapshot!(generation)
    transfer = transfer_params
    return if transfer.blank?

    result = Img2imgSourceTransfer.call(**transfer)
    result.apply_to!(generation)
    generation.source_image.attach(result.blob) unless generation.source_image.attached?
    generation.source_label ||= result.label
  end

  def transfer_params
    return @transfer_params if defined?(@transfer_params)

    @transfer_params =
      if params[:from_memo].present?
        { from_memo: params[:from_memo], attachment_id: params[:attachment_id] }
      elsif params[:from_image_generation].present?
        { from_image_generation: params[:from_image_generation], attachment: params[:attachment], attachment_id: params[:attachment_id] }
      elsif params[:from_img2img].present?
        { from_img2img: params[:from_img2img], attachment_id: params[:attachment_id] }
      elsif params[:img2img_generation].present?
        nested = params[:img2img_generation]
        if nested[:from_memo].present?
          { from_memo: nested[:from_memo], attachment_id: nested[:attachment_id] }
        elsif nested[:from_image_generation].present?
          { from_image_generation: nested[:from_image_generation], attachment: nested[:attachment], attachment_id: nested[:attachment_id] }
        elsif nested[:from_img2img].present?
          { from_img2img: nested[:from_img2img], attachment_id: nested[:attachment_id] }
        end
      end
  end

  def img2img_generation_params
    params.require(:img2img_generation).permit(
      :japanese_prompt,
      :prompt,
      :negative_prompt,
      :style_id,
      :aspect_ratio,
      :seed,
      :source_image,
      :source_label,
      :mask_image,
      :steps,
      :cfg_scale,
      :sampler_name,
      :vae_tiling,
      :denoising_strength,
      :use_source_dimensions,
      :generation_mode
    )
  end

  def apply_mode_attachments!(generation)
    attach_data_url_attachment!(generation, :mask_image, params[:mask]) if params[:mask].present?

    if params[:sketch_composite].present?
      attach_data_url_attachment!(generation, :sketch_image, params[:sketch_composite])
    end
  end

  def attach_data_url_attachment!(record, attachment_name, data_url)
    bytes = ImageDataUrlDecoder.decode(data_url)
    record.public_send(attachment_name).attach(
      io: StringIO.new(bytes),
      filename: "#{attachment_name}-#{SecureRandom.hex(4)}.png",
      content_type: "image/png"
    )
  rescue ImageDataUrlDecoder::Error => e
    record.errors.add(:base, e.message)
  end
end
