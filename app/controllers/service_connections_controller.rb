# frozen_string_literal: true

class ServiceConnectionsController < ApplicationController
  include LlamaServerAdminAuthentication

  before_action :require_llama_server_admin!
  before_action :set_service_connection, only: %i[show edit update destroy refresh_models openai_chat_models load_sampling bind_llama_server sync_llama_server]
  before_action :load_sampling_presets, only: %i[new create edit update]

  def index
    @service_connections = ServiceConnection.ordered
    @missing_builtin_keys = ServiceConnection.available_keys
  end

  def llama_servers
    @switchd_connection = ServiceConnection.find_by(key: "llama_switchd")
    @llama_server_operations = @switchd_connection&.llama_server_operations&.recent&.limit(30) || []
    @active_llama_server_operations = @llama_server_operations.select(&:active?).index_by(&:managed_server_id)
    @latest_llama_server_reconciliation = @switchd_connection&.llama_server_reconciliations&.recent&.first
    return unless @switchd_connection&.enabled?

    @inventory = LlamaSwitchdInventory.new(@switchd_connection).call
    @llama_server_usages = @inventory.servers.to_h do |server|
      [ server["id"], LlamaServerUsageResolver.descriptions_for_server(@switchd_connection, server["id"]) ]
    end
  rescue LlamaSwitchdClient::Error => e
    @inventory_error = e.message
  end

  def reconcile_llama_servers
    ServiceConnection.find_by!(key: "llama_switchd", enabled: true)
    LlamaServerReconciliationJob.perform_later
    redirect_to llama_servers_service_connections_path, notice: "LLMサーバーの整合チェックを受け付けました。"
  end

  def operate_llama_server
    connection = ServiceConnection.find_by!(key: "llama_switchd", enabled: true)
    action = params.require(:server_action)
    unless action.in?(LlamaServerOperation::LIFECYCLE_ACTIONS)
      redirect_to llama_servers_service_connections_path, alert: "許可されていないサーバー操作です。"
      return
    end
    usages = LlamaServerUsageResolver.descriptions_for_server(connection, params.require(:managed_server_id))
    if action == "stop" && usages.any? && !usage_acknowledged?
      redirect_to llama_servers_service_connections_path, alert: "使用中のサーバーを停止するには影響用途の確認が必要です。"
      return
    end
    operation = connection.llama_server_operations.create!(
      managed_server_id: params.require(:managed_server_id),
      action: action,
      request_payload: {}
    )
    LlamaServerOperationJob.perform_later(operation.id)
    redirect_to llama_servers_service_connections_path, notice: "#{operation.managed_server_id} の #{operation.action} を受け付けました。"
  rescue ActiveRecord::RecordNotUnique
    redirect_to llama_servers_service_connections_path, alert: "このサーバーでは別の操作を実行中です。"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to llama_servers_service_connections_path, alert: e.record.errors.full_messages.to_sentence
  end

  def bind_llama_server
    manager = ServiceConnection.find_by!(key: "llama_switchd", enabled: true)
    server_id = params.require(:managed_server_id)
    servers = LlamaSwitchdClient.new(base_url: manager.base_url, api_token: manager.api_token).list_servers
    raise LlamaSwitchdClient::Error, "指定した switchd server がありません" unless servers.any? { |server| server["id"] == server_id }

    @service_connection.update!(manager_connection: manager, managed_server_id: server_id)
    redirect_to llama_servers_service_connections_path, notice: "#{@service_connection.name} を #{server_id} に紐付けました。"
  rescue LlamaSwitchdClient::Error => e
    redirect_to llama_servers_service_connections_path, alert: e.message
  end

  def sync_llama_server
    LlamaSwitchdConnectionSync.new(@service_connection).call
    redirect_to llama_servers_service_connections_path, notice: "#{@service_connection.name} の URL と Alias を同期しました。"
  rescue LlamaSwitchdClient::Error, ActiveRecord::RecordInvalid => e
    redirect_to llama_servers_service_connections_path, alert: e.message
  end

  def show
  end

  def new
    @custom_llm = ActiveModel::Type::Boolean.new.cast(params[:custom])
    @service_connection = ServiceConnection.new(
      enabled: true,
      adapter: (@custom_llm ? "llama_cpp" : "generic"),
      sort_order: ServiceConnection.maximum(:sort_order).to_i + 1
    )
    @service_connection.key = "llm_" if @custom_llm
    @available_keys = ServiceConnection.available_keys unless @custom_llm
  end

  def create
    @service_connection = ServiceConnection.new(service_connection_params)
    @service_connection.adapter = "llama_cpp" if @service_connection.custom_llm?
    apply_searfront_settings!(@service_connection)
    apply_prompt_conversion_settings!(@service_connection)
    apply_llama_switchd_settings!(@service_connection)
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
    @service_connection.assign_attributes(service_connection_params)
    apply_searfront_settings!(@service_connection)
    apply_prompt_conversion_settings!(@service_connection)
    apply_llama_switchd_settings!(@service_connection)

    if @service_connection.save
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

  def load_sampling
    unless @service_connection.supports_prompt_conversion_settings?
      render json: { ok: false, error: "この接続ではサンプリング取得できません" }, status: :unprocessable_entity
      return
    end

    result = ServiceConnectionPropsFetcher.new(@service_connection).call
    if result.ok
      render json: {
        ok: true,
        message: result.message,
        sampling: result.sampling.to_h
      }
    else
      render json: { ok: false, error: result.message }, status: :unprocessable_entity
    end
  end

  def openai_chat_models
    unless @service_connection.openai?
      redirect_to @service_connection, alert: "この接続種別では Chat モデルを設定できません。"
      return
    end

    enabled = openai_chat_models_enabled_params
    @service_connection.assign_openai_chat_model_settings(
      catalog: @service_connection.openai_chat_model_settings.catalog,
      enabled: enabled
    )

    if @service_connection.save
      redirect_to @service_connection, notice: "Chat モデルを更新しました。"
    else
      redirect_to @service_connection, alert: @service_connection.errors.full_messages.to_sentence
    end
  end

  private

  def usage_acknowledged?
    ActiveModel::Type::Boolean.new.cast(params[:acknowledge_usage])
  end

  def set_service_connection
    @service_connection = ServiceConnection.find(params[:id])
  end

  def openai_chat_models_enabled_params
    params.require(:service_connection)
      .permit(openai_chat_models: { enabled: {} })
      .dig(:openai_chat_models, :enabled)
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

  def apply_searfront_settings!(connection)
    return unless connection.searfront?

    attrs = params.dig(:service_connection, :searfront_settings)
    connection.assign_searfront_settings(
      attrs.present? ? attrs.permit(
        :result_count,
        :concurrent_searches,
        :concurrent_fetches,
        :retry_count,
        :max_searches_per_turn,
        :max_fetches_per_turn
      ) : connection.settings
    )
  end

  def apply_prompt_conversion_settings!(connection)
    return unless connection.supports_prompt_conversion_settings?

    attrs = params.dig(:service_connection, :prompt_conversion_settings)
    return if attrs.blank?

    connection.assign_prompt_conversion_settings(
      attrs.permit(
        :json_schema,
        :enable_thinking,
        *LlmSamplingParams::KEYS
      )
    )
  end

  def apply_llama_switchd_settings!(connection)
    return unless connection.key.to_s == "llama_switchd"

    attrs = params.dig(:service_connection, :llama_switchd_settings)
    connection.assign_llama_switchd_settings(attrs.present? ? attrs.permit(:public_host) : {})
  end

  def load_sampling_presets
    @llm_sampling_presets = LlmSamplingPreset.enabled.ordered
  end

  def load_model_options
    result = ServiceConnectionModelFetcher.new(@service_connection).call
    @model_options = result.models if result.ok
    @model_options_error = result.message unless result.ok
  end

  def sync_server_model!(models)
    if @service_connection.openai?
      sync_openai_chat_models!(models)
      return
    end

    return if models.blank?
    return if @service_connection.server_model.present? && models.include?(@service_connection.server_model)

    @service_connection.update!(server_model: models.first)
  end

  def sync_openai_chat_models!(models)
    chat_models = OpenaiChatModels.filter(models)
    return if chat_models.empty?

    settings = (@service_connection.settings || {}).merge(
      OpenaiChatModelSettings.merge_catalog(@service_connection.settings, chat_models)
    )
    attrs = { settings: settings }
    enabled = OpenaiChatModelSettings.from(settings).enabled
    attrs[:server_model] = @service_connection.server_model.presence || enabled.first
    @service_connection.update!(attrs)
    ChatModelCatalog.seed!
  end
end
