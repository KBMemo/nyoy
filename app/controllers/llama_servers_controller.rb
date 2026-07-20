# frozen_string_literal: true

class LlamaServersController < ApplicationController
  include LlamaServerAdminAuthentication

  before_action :require_llama_server_admin!
  before_action :set_switchd_connection

  def new
    @definition = LlamaServerDefinition.new(port: suggested_port, slots: 1)
    load_models
  end

  def create
    @definition = LlamaServerDefinition.new(definition_params)
    return render_new unless @definition.valid?

    enqueue_operation!("create", @definition.server_id, "values" => @definition.values.compact)
    redirect_to llama_servers_service_connections_path, notice: "#{@definition.server_id} の定義作成を受け付けました。"
  rescue ActiveRecord::RecordNotUnique
    redirect_to llama_servers_service_connections_path, alert: "このサーバーでは別の操作を実行中です。"
  end

  def edit
    detail = client.get_server(params[:id])
    @definition = LlamaServerDefinition.from_api(server_id: params[:id], values: detail.fetch("values"))
    load_models
  rescue LlamaSwitchdClient::Error, KeyError => e
    redirect_to llama_servers_service_connections_path, alert: e.message
  end

  def update
    @definition = LlamaServerDefinition.new(definition_params.merge(server_id: params[:id]))
    return render_edit unless @definition.valid?

    enqueue_operation!("update", params[:id], "values" => @definition.values)
    redirect_to llama_servers_service_connections_path, notice: "#{params[:id]} の定義更新を受け付けました。"
  rescue ActiveRecord::RecordNotUnique
    redirect_to llama_servers_service_connections_path, alert: "このサーバーでは別の操作を実行中です。"
  end

  def destroy
    server = client.get_server(params[:id]).fetch("server")
    if server["active"] || server["enabled"]
      redirect_to llama_servers_service_connections_path, alert: "削除前にサーバーを停止し、自動起動を無効化してください。"
      return
    end

    enqueue_operation!("delete", params[:id], {})
    redirect_to llama_servers_service_connections_path, notice: "#{params[:id]} の定義削除を受け付けました。"
  rescue ActiveRecord::RecordNotUnique
    redirect_to llama_servers_service_connections_path, alert: "このサーバーでは別の操作を実行中です。"
  rescue LlamaSwitchdClient::Error, KeyError => e
    redirect_to llama_servers_service_connections_path, alert: e.message
  end

  private

  def set_switchd_connection
    @switchd_connection = ServiceConnection.find_by!(key: "llama_switchd", enabled: true)
  end

  def client
    @client ||= LlamaSwitchdClient.new(base_url: @switchd_connection.base_url, api_token: @switchd_connection.api_token)
  end

  def definition_params
    params.require(:llama_server_definition).permit(
      :server_id, :source_type, :model, :hf_repo, :port, :server_alias, :host,
      :ctx_size, :slots, :batch_size, :ubatch_size, :threads, :threads_batch,
      :n_gpu_layers, :device, :flash_attn, :embedding, :jinja, :mmproj,
      :mmproj_offload, :draft, :device_draft, :spec_type, :spec_draft_n_max
    )
  end

  def enqueue_operation!(action, server_id, payload)
    operation = @switchd_connection.llama_server_operations.create!(
      action: action,
      managed_server_id: server_id,
      request_payload: payload
    )
    LlamaServerOperationJob.perform_later(operation.id)
  end

  def load_models
    @models = client.list_models
  rescue LlamaSwitchdClient::Error => e
    @models = []
    @models_error = e.message
  end

  def suggested_port
    used = client.list_servers.filter_map { |server| Integer(server["port"], exception: false) }
    (10_110..10_199).find { |port| !used.include?(port) }
  rescue LlamaSwitchdClient::Error
    10_110
  end

  def render_new
    load_models
    render :new, status: :unprocessable_entity
  end

  def render_edit
    load_models
    render :edit, status: :unprocessable_entity
  end
end
