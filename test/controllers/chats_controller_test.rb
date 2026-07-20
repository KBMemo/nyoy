# frozen_string_literal: true

require "base64"
require "test_helper"

class ChatsControllerTest < ActionDispatch::IntegrationTest
  setup do
    ChatModelCatalog.seed!
    LlmSamplingPresetSeeds.seed!
  end

  test "index renders chat list" do
    get chats_path
    assert_response :success
    assert_select "h1", text: "チャット"
    assert_select "a", text: "新しいチャット"
  end

  test "new renders chat form" do
    get new_chat_path
    assert_response :success
    assert_select "textarea[name='chat[prompt]']"
    assert_select "input[type=file][name='chat[attachments]']"
    assert_select "select[name='chat[model]'] optgroup", minimum: 2
    assert_select "select[name='chat[model]'] optgroup[label='Gemma 4 E4B'] option", text: "gemma-4-e4b-it-qat-ud-q4-k-xl"
    assert_select "select[name='chat[model]'] optgroup[label='GPT-OSS'] option", text: "gpt-oss"
    assert_select "button[aria-label='チャット設定'] svg.nyoy-chat-settings-icon"
    assert_select "#new_chat_settings_dialog"
    assert_select "#new_chat_sampling_preset_select"
    assert_select "input[name='chat[temperature]']"
    assert_select "input[name='chat[max_tokens]']"
    assert_select "select[name='chat[reasoning_effort]']"
  end

  test "new syncs gpt-oss model when it was missing from models table" do
    Model.where(provider: "openai", model_id: "gpt-oss").delete_all

    get new_chat_path

    assert Model.exists?(provider: "openai", model_id: "gpt-oss")
    assert_select "select[name='chat[model]'] option", text: "gpt-oss"
  end

  test "create enqueues chat response job with selected model" do
    model = Model.find_by!(provider: "openai", model_id: "gpt-oss")

    assert_enqueued_with(job: ChatResponseJob) do
      post chats_path, params: { chat: { prompt: "こんにちは", model: model.id } }
    end

    chat = Chat.order(:created_at).last
    assert_redirected_to chat_path(chat)
    assert_equal model, chat.model
  end

  test "create seeds llm_params from AppSetting default sampling preset" do
    AppSetting.delete_all
    AppSetting.instance.update!(default_llm_sampling_preset_key: "qwen3_5_9b")
    model = Model.find_by!(provider: "openai", model_id: "gpt-oss")

    post chats_path, params: { chat: { prompt: "こんにちは", model: model.id } }

    chat = Chat.order(:created_at).last
    assert_in_delta 0.7, chat.llm_params["temperature"]
    assert_in_delta 0.8, chat.llm_params["top_p"]
  end

  test "create seeds max_tokens from connection profile over app preset" do
    AppSetting.delete_all
    AppSetting.instance.update!(default_llm_sampling_preset_key: "qwen3_5_9b")
    model = Model.find_by!(provider: "openai", model_id: "gpt-oss")
    connection = ServiceConnection.find_by!(key: "gpt_oss")
    connection.assign_prompt_conversion_settings(
      connection.prompt_conversion_settings.to_settings_h.merge("max_tokens" => 4096)
    )
    connection.save!

    post chats_path, params: { chat: { prompt: "こんにちは", model: model.id } }

    chat = Chat.order(:created_at).last
    assert_equal 4096, chat.llm_params["max_tokens"]
  end

  test "create uses sampling params submitted on new chat form" do
    model = Model.find_by!(provider: "openai", model_id: "gpt-oss")

    post chats_path, params: {
      chat: {
        prompt: "こんにちは",
        model: model.id,
        temperature: "0.3",
        max_tokens: "512",
        top_p: "0.9",
        reasoning_effort: "low"
      }
    }

    chat = Chat.order(:created_at).last
    assert_in_delta 0.3, chat.llm_params["temperature"]
    assert_equal 512, chat.llm_params["max_tokens"]
    assert_in_delta 0.9, chat.llm_params["top_p"]
    assert_equal "low", chat.llm_params["reasoning_effort"]
  end

  test "create enqueues chat response job" do
    model = Model.find_by!(provider: "openai", model_id: "gemma-4-e4b-it-qat-ud-q4-k-xl")

    assert_enqueued_with(job: ChatResponseJob) do
      post chats_path, params: { chat: { prompt: "こんにちは", model: model.id } }
    end

    chat = Chat.order(:created_at).last
    assert_redirected_to chat_path(chat)
    assert_equal model, chat.model
  end

  test "create validates blank prompt without attachment" do
    post chats_path, params: { chat: { prompt: "  " } }
    assert_response :unprocessable_entity
  end

  test "create starts chat with image attachment only" do
    model = Model.find_by!(provider: "openai", model_id: "gpt-oss")
    png = Base64.decode64(
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
    )

    assert_enqueued_with(job: ChatResponseJob) do
      post chats_path, params: {
        chat: {
          prompt: "",
          model: model.id,
          attachments: Rack::Test::UploadedFile.new(
            StringIO.new(png),
            "image/png",
            original_filename: "pixel.png"
          )
        }
      }
    end

    chat = Chat.order(:created_at).last
    message = chat.messages.where(role: :user).order(:id).last
    assert_redirected_to chat_path(chat)
    assert message.attachments.attached?
  end

  test "show renders chat thread" do
    chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gemma-4-e4b-it-qat-ud-q4-k-xl"))

    get chat_path(chat)
    assert_response :success
    assert_select "#messages"
    assert_select "textarea[name='message[content]']"
    assert_select "input[type=file][name='message[attachments]']"
  end

  test "show renders cancelled assistant message" do
    chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
    chat.messages.create!(
      role: :assistant,
      content: "#{ChatCancellationBroadcaster::CANCELLED_PREFIX}応答を中止しました。"
    )

    get chat_path(chat)

    assert_response :success
    assert_select ".nyoy-chat-message-cancelled", text: /応答を中止しました/
  end

  test "show renders chat settings dialog with model and web tool fields when searfront is enabled" do
    chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
    service_connections(:searfront).update!(enabled: true)

    get chat_path(chat)

    assert_response :success
    assert_select "dialog#chat_settings_dialog"
    assert_select "button[aria-label='チャット設定'] svg.nyoy-chat-settings-icon"
    assert_select "dialog#chat_settings_dialog input[name='temperature']"
    assert_select "dialog#chat_settings_dialog input[name='top_p']"
    assert_select "dialog#chat_settings_dialog #chat_sampling_preset_select"
    assert_select "dialog#chat_settings_dialog #chat_sampling_preset_select option[value]", minimum: 2
    assert_select "dialog#chat_settings_dialog button[data-action='prompt-conversion-settings#applyPreset']"
    assert_select "dialog#chat_settings_dialog input[name='max_searches_per_turn']"
    assert_select "dialog#chat_settings_dialog input[name='max_fetches_per_turn']"
    assert_select "section h2", text: "Web ツール上限", count: 0
  end

  test "update_chat_settings persists llm params and searfront settings" do
    chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
    connection = service_connections(:searfront)
    connection.update!(enabled: true)

    patch chat_settings_chat_path(chat), params: {
      temperature: 0.8,
      top_p: 0.9,
      max_tokens: 2048,
      top_k: 40,
      repeat_penalty: 1.1,
      min_p: 0.05,
      max_searches_per_turn: 4,
      max_fetches_per_turn: 6
    }

    assert_redirected_to chat_path(chat)
    assert_equal(
      {
        "temperature" => 0.8,
        "top_p" => 0.9,
        "max_tokens" => 2048,
        "top_k" => 40,
        "repeat_penalty" => 1.1,
        "min_p" => 0.05
      },
      chat.reload.llm_params
    )
    settings = connection.reload.searfront_settings
    assert_equal 4, settings.max_searches_per_turn
    assert_equal 6, settings.max_fetches_per_turn
  end

  test "update_chat_settings persists llm params without searfront" do
    chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
    service_connections(:searfront).update!(enabled: false)

    patch chat_settings_chat_path(chat), params: {
      temperature: 0.6,
      top_p: "",
      max_tokens: "",
      top_k: "",
      repeat_penalty: "",
      min_p: ""
    }

    assert_redirected_to chat_path(chat)
    assert_equal({ "temperature" => 0.6 }, chat.reload.llm_params)
  end

  test "cancel marks running chat as cancelled" do
    chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"), response_state: "running")

    post cancel_chat_path(chat)

    assert_redirected_to chat_path(chat)
    assert_equal "cancelled", chat.reload.response_state
  end

  test "show renders assistant markdown as html" do
    chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gemma-4-e4b-it-qat-ud-q4-k-xl"))
    chat.messages.create!(role: :assistant, content: "### 見出し\n\n**太字**")

    get chat_path(chat)

    assert_response :success
    assert_select "#message_#{chat.messages.last.id}_content h3", text: "見出し"
    assert_select "#message_#{chat.messages.last.id}_content strong", text: "太字"
  end

  test "show restores running agent progress panel" do
    model = Model.find_by!(provider: "openai", model_id: "gpt-oss")
    chat = Chat.create!(model: model)
    run = chat.agent_runs.create!(
      graph_name: AgentGraph::ResearchGraph::NAME,
      status: "running",
      current_node: "finalize_answer",
      started_at: 1.minute.ago,
      state: { "question" => "調べて" }
    )
    run.agent_node_runs.create!(
      node_name: "finalize_answer",
      status: "running",
      started_at: 10.seconds.ago
    )

    get chat_path(chat)

    assert_response :success
    assert_select "#agent_run_progress_panel"
    assert_select "#agent_run_progress_panel", text: /最終回答を生成しています/
    assert_select "#agent_run_progress_panel[data-node-started-at]"
  end

  test "show links recent agent runs" do
    model = Model.find_by!(provider: "openai", model_id: "gpt-oss")
    chat = Chat.create!(model: model)
    run = chat.agent_runs.create!(
      graph_name: AgentGraph::ResearchGraph::NAME,
      status: "completed",
      current_node: nil,
      started_at: 1.minute.ago,
      finished_at: Time.current,
      state: { "question" => "調べて", "final_answer" => "回答" }
    )

    get chat_path(chat)

    assert_response :success
    assert_select "h2", text: "AgentRun"
    assert_select "a[href='#{chat_agent_run_path(chat, run)}']", text: "詳細"
  end

  test "show summarizes failed agent runs in history" do
    model = Model.find_by!(provider: "openai", model_id: "gpt-oss")
    chat = Chat.create!(model: model)
    run = chat.agent_runs.create!(
      graph_name: AgentGraph::ResearchGraph::NAME,
      status: "failed",
      current_node: "finalize_answer",
      started_at: 1.minute.ago,
      finished_at: Time.current,
      state: { "question" => "調べて" },
      error_message: "connection failed"
    )
    run.agent_node_runs.create!(
      node_name: "finalize_answer",
      status: "failed",
      error_message: "node connection failed"
    )
    checkpoint = run.agent_checkpoints.create!(node_name: "synthesize_draft", state: run.state)

    get chat_path(chat)

    assert_response :success
    assert_select "h2", text: "AgentRun"
    assert_select "p", text: /失敗 node: finalize_answer/
    assert_select "p", text: /最後の checkpoint: synthesize_draft ##{checkpoint.id}/
    assert_select "p", text: /node connection failed/
  end

  test "show summarizes retry runs in history" do
    model = Model.find_by!(provider: "openai", model_id: "gpt-oss")
    chat = Chat.create!(model: model)
    source = chat.agent_runs.create!(
      graph_name: AgentGraph::ResearchGraph::NAME,
      status: "failed",
      current_node: "finalize_answer",
      state: { "question" => "調べて" }
    )
    retry_run = chat.agent_runs.create!(
      graph_name: AgentGraph::ResearchGraph::NAME,
      status: "completed",
      current_node: nil,
      state: {
        "retry_of_agent_run_id" => source.id,
        "retry_from_checkpoint_id" => 789,
        "retry_from_node" => "synthesize_draft"
      }
    )

    get chat_path(chat)

    assert_response :success
    assert_select "a[href='#{chat_agent_run_path(chat, retry_run)}']", text: "詳細"
    assert_select "a[href='#{chat_agent_run_path(chat, source)}']", text: "##{source.id}"
    assert_select "p", text: /checkpoint #789/
    assert_select "p", text: /from synthesize_draft/
    assert_select "p", text: /retried: 1 run/
  end

  test "show renders empty agent run history for image-only chat turns" do
    model = Model.find_by!(provider: "openai", model_id: "gpt-oss")
    chat = Chat.create!(model: model)
    message = chat.messages.create!(role: :user, content: ChatImageAttachments::PLACEHOLDER)
    png = Base64.decode64(
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
    )
    message.attachments.attach(io: StringIO.new(png), filename: "pixel.png", content_type: "image/png")

    get chat_path(chat)

    assert_response :success
    assert_select "h2", text: "AgentRun"
    assert_select "section", text: /Graph 実行履歴はありません/
  end

  test "show renders assistant timing and model stats" do
    model = Model.find_by!(provider: "openai", model_id: "gpt-oss")
    chat = Chat.create!(model: model)
    message = chat.messages.create!(
      role: :assistant,
      content: "回答",
      model: model,
      response_elapsed_ms: 12_345,
      thinking_elapsed_ms: 4567,
      llama_cache_prompt: true,
      llama_cache_slot_id: 2,
      llama_cache_slot_count: 4,
      input_tokens: 160,
      output_tokens: 40,
      cached_tokens: 120,
      cache_creation_tokens: 30
    )

    get chat_path(chat)

    assert_response :success
    assert_select "#message_#{message.id} .nyoy-chat-message-stat", minimum: 3
    assert_select "#message_#{message.id} .nyoy-chat-message-stat dd", text: "gpt-oss"
    assert_select "#message_#{message.id} .nyoy-chat-message-stat dd", text: "12.3秒"
    assert_select "#message_#{message.id} .nyoy-chat-message-stat dd", text: "4.6秒"
    assert_select "#message_#{message.id} .nyoy-chat-message-stat dt", text: "KV cache"
    assert_select "#message_#{message.id} .nyoy-chat-message-stat dd", text: "prompt / slot 2/4"
    assert_select "#message_#{message.id} .nyoy-chat-message-stat dt", text: "tokens"
    assert_select "#message_#{message.id} .nyoy-chat-message-stat dd", text: "in 160 / out 40 / cached 120 / created 30"
  end
end
