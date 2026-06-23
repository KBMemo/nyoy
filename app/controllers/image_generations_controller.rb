# frozen_string_literal: true

class ImageGenerationsController < ApplicationController
  before_action :set_image_generation, only: :show
  before_action :load_catalog, only: %i[index new create]

  def index
    @image_generations = ImageGeneration.recent.limit(20)
    @current_sd_model = @catalog.current_model
  end

  def show
  end

  def new
    @image_generation = ImageGeneration.new(
      sd_model: @sd_models.first,
      width: 512,
      height: 512,
      steps: 20,
      cfg_scale: 7.0
    )
  end

  def create
    @image_generation = ImageGeneration.new(image_generation_params)

    if @image_generation.save
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

  def load_catalog
    @catalog = SdModelCatalog.new
    @sd_models = @catalog.model_names
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
