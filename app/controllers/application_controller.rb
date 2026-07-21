class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern
  private

  def available_chat_models
    ChatModelCatalog.seed! if ServiceConnection.model_endpoints.enabled.any?

    Model.where(provider: "openai", model_id: ChatModelCatalog.model_ids).order(:name)
  end

  def load_style_plan_connection_options
    ChatModelCatalog.seed! if ServiceConnection.model_endpoints.enabled.any?
    @style_plan_connection_options = StylePlanModelCatalog.options_for_select
  end
end
