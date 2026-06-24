# frozen_string_literal: true

class ImageGenerationsController < ApplicationController
  include SdCatalogLoadable

  before_action :set_image_generation, only: :show
  before_action :load_sd_catalog, only: %i[index new create]

  def index
    @image_generations = ImageGeneration.recent.limit(20)
  end

  def show
  end

  def new
    @image_generation = ImageGeneration.new(
      sd_model: resolve_sd_model,
      width: 512,
      height: 512,
      steps: 20,
      cfg_scale: 7.0
    )
  end

  def create
    @image_generation = ImageGeneration.new(image_generation_params)

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

  def image_generation_params
    params.require(:image_generation).permit(
      :japanese_prompt,
      :negative_prompt,
      :sd_model,
      :width,
      :height,
      :steps,
      :cfg_scale,
      :seed
    )
  end
end
