# frozen_string_literal: true

class ImageGenerationsController < ApplicationController
  before_action :set_image_generation, only: %i[show refine]
  before_action :load_generation_options, only: %i[index new create translate_prompt show refine]

  def index
    @image_generations = ImageGeneration.recent.limit(20)
  end

  def show
  end

  def refine
    unless @image_generation.refineable?
      redirect_to @image_generation, alert: "このラフ案では仕上げ生成できません"
      return
    end

    draft_index = params[:draft_index].to_i
    unless draft_index.in?(0...@image_generation.drafts.count)
      redirect_to @image_generation, alert: "ラフ案を選択してください"
      return
    end

    refine_params = refine_image_generation_params
    attrs = {
      selected_draft_index: draft_index,
      status: "refining",
      image_started_at: Time.current,
      image_finished_at: nil,
      finished_at: nil,
      error_message: nil
    }
    attrs[:refine_denoising_strength] = refine_params[:refine_denoising_strength] if refine_params.key?(:refine_denoising_strength)
    attrs[:refine_steps] = refine_params[:refine_steps].presence if refine_params.key?(:refine_steps)
    attrs[:enable_hires] = refine_params[:enable_hires] == "1" if refine_params.key?(:enable_hires)
    attrs[:hires_upscaler] = refine_params[:hires_upscaler] if refine_params[:hires_upscaler].present?
    attrs[:hires_scale] = refine_params[:hires_scale] if refine_params[:hires_scale].present?
    attrs[:hires_steps] = refine_params[:hires_steps].presence if refine_params.key?(:hires_steps)
    attrs[:hires_denoising_strength] = refine_params[:hires_denoising_strength] if refine_params.key?(:hires_denoising_strength)
    attrs[:refine_render_preset_id] = refine_params[:refine_render_preset_id].presence if refine_params.key?(:refine_render_preset_id)

    @image_generation.update!(attrs)
    RefineImageJob.perform_later(@image_generation.id)
    redirect_to @image_generation
  end

  def new
    @image_generation = build_new_image_generation
  end

  def create
    @image_generation = ImageGeneration.new(image_generation_params)
    apply_render_presets!(@image_generation)

    if @image_generation.save
      GenerateImageJob.perform_later(@image_generation.id)
      redirect_to @image_generation
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

  def set_image_generation
    @image_generation = ImageGeneration.find(params[:id])
  end

  def load_generation_options
    @prompt_styles = PromptStyle.enabled.ordered
    @draft_render_presets = RenderPreset.of_kind("draft").ordered
    @refine_render_presets = RenderPreset.of_kind("refine").ordered
  end

  def build_new_image_generation
    generation = ImageGeneration.new(
      width: 768,
      height: 768,
      steps: 22,
      cfg_scale: 6.0,
      sampler_name: "euler_a",
      vae_tiling: true,
      draft_batch_size: 4,
      refine_denoising_strength: 0.4,
      enable_hires: true,
      hires_upscaler: "Latent",
      hires_scale: 1.5,
      hires_denoising_strength: 0.35
    )

    if params[:copy_from].present?
      source = ImageGeneration.find_by(id: params[:copy_from])
      source&.apply_settings_to(generation)
    else
      apply_default_render_presets!(generation)
    end

    generation
  end

  def apply_default_render_presets!(generation)
    RenderPreset.default_for_kind("draft")&.apply_draft_to(generation)
    RenderPreset.default_for_kind("refine")&.apply_refine_to(generation)
  end

  def apply_render_presets!(generation)
    RenderPreset.find_by(id: generation.render_preset_id)&.apply_draft_to(generation)
    RenderPreset.find_by(id: generation.refine_render_preset_id)&.apply_refine_to(generation)
  end

  def image_generation_params
    params.require(:image_generation).permit(
      :japanese_prompt,
      :prompt,
      :negative_prompt,
      :style_id,
      :aspect_ratio,
      :seed,
      :render_preset_id,
      :refine_render_preset_id,
      :draft_batch_size,
      :draft_steps,
      :refine_steps,
      :refine_denoising_strength,
      :enable_hires,
      :hires_upscaler,
      :hires_scale,
      :hires_steps,
      :hires_denoising_strength
    )
  end

  def refine_image_generation_params
    params.permit(
      :refine_render_preset_id,
      :refine_denoising_strength,
      :refine_steps,
      :enable_hires,
      :hires_upscaler,
      :hires_scale,
      :hires_steps,
      :hires_denoising_strength
    )
  end
end
