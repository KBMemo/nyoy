# frozen_string_literal: true

class ServiceConnectionsController < ApplicationController
  before_action :set_service_connection, only: %i[show edit update destroy refresh_models]

  def index
    @service_connections = ServiceConnection.ordered
    @missing_builtin_keys = ServiceConnection.available_keys
  end

  def show
  end

  def new
    @custom_llm = ActiveModel::Type::Boolean.new.cast(params[:custom])
    @service_connection = ServiceConnection.new(
      enabled: true,
      sort_order: ServiceConnection.maximum(:sort_order).to_i + 1
    )
    @service_connection.key = "llm_" if @custom_llm
    @available_keys = ServiceConnection.available_keys unless @custom_llm
  end

  def create
    @service_connection = ServiceConnection.new(service_connection_params)
    @custom_llm = @service_connection.custom_llm?
    @available_keys = ServiceConnection.available_keys unless @custom_llm

    if @service_connection.save
      redirect_to @service_connection, notice: "接続を登録しました。"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def seed_missing
    count = ServiceConnectionSeeds.seed_missing!
    message = count.positive? ? "組み込み接続 #{count} 件を登録しました。" : "未登録の組み込み接続はありません。"
    redirect_to service_connections_path, notice: message
  end

  def edit
    load_model_options
  end

  def update
    if @service_connection.update(service_connection_params)
      redirect_to @service_connection, notice: "接続を更新しました。"
    else
      load_model_options
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @service_connection.destroy
      redirect_to service_connections_path, notice: "接続を削除しました。"
    else
      redirect_to @service_connection, alert: @service_connection.errors.full_messages.to_sentence
    end
  end

  def refresh_models
    result = ServiceConnectionModelFetcher.new(@service_connection).call

    if result.ok
      sync_server_model!(result.models)
      redirect_to @service_connection, notice: result.message
    else
      redirect_to @service_connection, alert: result.message
    end
  end

  private

  def set_service_connection
    @service_connection = ServiceConnection.find(params[:id])
  end

  def service_connection_params
    permitted = params.require(:service_connection).permit(
      :key,
      :name,
      :base_url,
      :server_model,
      :api_token,
      :enabled,
      :sort_order,
      :notes
    )
    permitted.delete(:key) if @service_connection&.persisted?
    permitted.delete(:api_token) if permitted[:api_token].blank?
    permitted
  end

  def load_model_options
    result = ServiceConnectionModelFetcher.new(@service_connection).call
    @model_options = result.models if result.ok
    @model_options_error = result.message unless result.ok
  end

  def sync_server_model!(models)
    return if models.blank?
    return if @service_connection.server_model.present? && models.include?(@service_connection.server_model)

    @service_connection.update!(server_model: models.first)
  end
end
