# frozen_string_literal: true

class ImageGenerationsController < ApplicationController
  include SdCatalogLoadable
  include LoraParamsParseable

  before_action :set_image_generation, only: :show
  before_action :load_sd_catalog, only: %i[index new create]
  before_action :load_generation_options, only: %i[new create]

  def index
    @image_generations = ImageGeneration.recent.limit(20)
  end

  def show
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
      :prompt_skill_id
    )
  end
end
