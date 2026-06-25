# frozen_string_literal: true

class GenerationPresetsController < ApplicationController
  include SdCatalogLoadable
  include LoraParamsParseable

  before_action :set_generation_preset, only: %i[show edit update destroy]
  before_action :load_sd_catalog, only: %i[index new create edit update]
  before_action :load_generation_options, only: %i[new create edit update]

  def index
    @draft_presets = GenerationPreset.draft.includes(:prompt_skill).ordered
    @refine_presets = GenerationPreset.refine.ordered
  end

  def show
  end

  def new
    kind = params[:preset_kind].presence_in(GenerationPreset::PRESET_KINDS) || "draft"
    @generation_preset = build_new_preset(kind)
  end

  def create
    @generation_preset = GenerationPreset.new(generation_preset_params)
    assign_loras_from_param(@generation_preset, params.dig(:generation_preset, :loras))

    if !@generation_preset.refine? && !sd_model_available?(@generation_preset.sd_model)
      @generation_preset.errors.add(:sd_model, "は利用できません")
    end

    if @generation_preset.errors.empty? && @generation_preset.save
      redirect_to @generation_preset, notice: "プリセットを作成しました。"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    @generation_preset.assign_attributes(generation_preset_params)
    assign_loras_from_param(@generation_preset, params.dig(:generation_preset, :loras))

    if !@generation_preset.refine? && !sd_model_available?(@generation_preset.sd_model)
      @generation_preset.errors.add(:sd_model, "は利用できません")
    end

    if @generation_preset.errors.empty? && @generation_preset.save
      redirect_to @generation_preset, notice: "プリセットを更新しました。"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @generation_preset.destroy!
    redirect_to generation_presets_path, notice: "プリセットを削除しました。"
  end

  private

  def set_generation_preset
    @generation_preset = GenerationPreset.find(params[:id])
  end

  def load_generation_options
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

  def build_new_preset(kind)
    base = {
      preset_kind: kind,
      sd_model: resolve_sd_model,
      width: 768,
      height: 768,
      steps: 22,
      cfg_scale: 6.0,
      sampler_name: "euler_a",
      vae_tiling: true,
      loras: "[]"
    }

    if kind == "refine"
      GenerationPreset.new(
        base.merge(
          refine_denoising_strength: 0.4,
          enable_hires: true,
          hires_upscaler: "Latent",
          hires_scale: 1.5,
          hires_denoising_strength: 0.35
        )
      )
    else
      GenerationPreset.new(base.merge(draft_batch_size: 4))
    end
  end

  def generation_preset_params
    params.require(:generation_preset).permit(
      :name,
      :preset_kind,
      :sd_model,
      :width,
      :height,
      :steps,
      :cfg_scale,
      :sampler_name,
      :vae_tiling,
      :default,
      :prompt_skill_id,
      :default_negative_prompt,
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
end
