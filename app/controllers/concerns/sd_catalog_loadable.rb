# frozen_string_literal: true

module SdCatalogLoadable
  extend ActiveSupport::Concern

  private

  def load_sd_catalog
    @catalog = SdModelCatalog.new
    @sd_models = @catalog.model_names
    @current_sd_model = @catalog.current_model
  rescue SdModelCatalog::Unavailable => e
    @catalog_error = e.message
    @sd_models = []
    @current_sd_model = nil
  end

  def resolve_sd_model
    @current_sd_model.presence || @sd_models.first
  end

  def sd_model_available?(model)
    model.present? && @sd_models.include?(model)
  end
end
