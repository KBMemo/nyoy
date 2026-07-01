# frozen_string_literal: true

class ServiceConnectionsController < ApplicationController
  before_action :set_service_connection, only: %i[show edit update destroy probe]

  def index
    @service_connections = ServiceConnection.ordered
  end

  def show
  end

  def new
    @service_connection = ServiceConnection.new(
      enabled: true,
      sort_order: ServiceConnection.maximum(:sort_order).to_i + 1
    )
    @available_keys = ServiceConnection.available_keys
  end

  def create
    @service_connection = ServiceConnection.new(service_connection_params)
    @available_keys = ServiceConnection.available_keys

    if @service_connection.save
      redirect_to @service_connection, notice: "接続を登録しました。"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @service_connection.update(service_connection_params)
      redirect_to @service_connection, notice: "接続を更新しました。"
    else
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

  def probe
    result = ServiceConnectionProbe.new(@service_connection).call
    message = format_probe_message(result)

    if result.ok
      redirect_to @service_connection, notice: message
    else
      redirect_to @service_connection, alert: message
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

  def format_probe_message(result)
    prefix = result.ok ? "疎通確認 OK" : "疎通確認 NG"
    "#{prefix}（#{result.latency_ms}ms）: #{result.message}"
  end
end
