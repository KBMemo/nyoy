# frozen_string_literal: true

class ImageGenerationsController < ApplicationController
  include SdCatalogLoadable
  include LoraParamsParseable

  before_action :set_image_generation, only: %i[show refine]
  before_action :load_sd_catalog, only: %i[index new create translate_prompt]
  before_action :load_generation_options, only: %i[new create translate_prompt]

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
    attrs[:hires_denoising_strength] = refine_params[:hires_denoising_strength] if refine_params[:hires_denoising_strength].present?
    attrs[:hires_steps] = refine_params[:hires_steps].presence if refine_params.key?(:hires_steps)

    @image_generation.update!(attrs)
    RefineImageJob.perform_later(@image_generation.id)
    redirect_to @image_generation
  end

  def new
    @image_generation = build_new_image_generation
  end

  def create
    @image_generation = ImageGeneration.new(image_generation_params)
    assign_loras_from_param(@image_generation, params.dig(:image_generation, :loras))

    unless sd_model_available?(@image_generation.sd_model)
      @image_generation.errors.add(:sd_model, "は利用できません")
    end

    if @image_generation.errors.empty? && @image_generation.save
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

    skill = PromptSkill.find_by(id: params[:prompt_skill_id])
    prompt = SdPromptTranslator.new.translate(japanese_prompt, skill: skill)
    render json: { prompt: prompt }
  rescue SdPromptTranslator::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def set_image_generation
    @image_generation = ImageGeneration.find(params[:id])
  end

  def load_generation_options
    @generation_presets = GenerationPreset.includes(:prompt_skill).ordered
    @prompt_skills = PromptSkill.ordered
    load_sd_loras_and_samplers
  end

  def load_sd_loras_and_samplers
    @sd_loras = SdLoraCatalog.new.list
    @sd_samplers = SdSamplerCatalog.new.names
  rescue SdLoraCatalog::Error, SdSamplerCatalog::Error => e
    @lora_catalog_error = e.message
    @sd_loras = []
    @sd_samplers = %w[euler_a]
  end

  def apply_selected_preset(generation)
    preset = if params[:generation_preset_id].present?
      GenerationPreset.find_by(id: params[:generation_preset_id])
    else
      GenerationPreset.default_for_generation
    end

    return unless preset

    preset.apply_to(generation)
    generation.sd_model = resolve_sd_model unless sd_model_available?(generation.sd_model)
  end

  def build_new_image_generation
    generation = ImageGeneration.new(
      sd_model: resolve_sd_model,
      width: 512,
      height: 512,
      steps: 20,
      cfg_scale: 7.0,
      sampler_name: "euler_a",
      vae_tiling: false,
      loras: "[]"
    )

    if params[:copy_from].present?
      source = ImageGeneration.find_by(id: params[:copy_from])
      source&.apply_settings_to(generation)
    else
      apply_selected_preset(generation)
    end

    generation.sd_model = resolve_sd_model unless sd_model_available?(generation.sd_model)
    generation
  end

  def image_generation_params
    params.require(:image_generation).permit(
      :japanese_prompt,
      :prompt,
      :negative_prompt,
      :sd_model,
      :width,
      :height,
      :steps,
      :cfg_scale,
      :seed,
      :sampler_name,
      :vae_tiling,
      :generation_preset_id,
      :prompt_skill_id,
      :draft_batch_size,
      :draft_steps,
      :refine_steps,
      :refine_denoising_strength
    )
  end

  def refine_image_generation_params
    params.permit(
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
