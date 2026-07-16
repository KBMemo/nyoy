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
    assert_select "select[name='chat[model]'] optgroup[label='Gemma Vision'] option", text: "gemma-4-12b-it-vision-mtp"
    assert_select "select[name='chat[model]'] optgroup[label='GPT-OSS'] option", text: "gpt-oss"
    assert_select "button[aria-label='チャット設定'] svg.nyoy-chat-settings-icon"
    assert_select "#new_chat_settings_dialog"
    assert_select "#new_chat_sampling_preset_select"
    assert_select "input[name='chat[temperature]']"
    assert_select "input[name='chat[max_tokens]']"
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
        top_p: "0.9"
      }
    }

    chat = Chat.order(:created_at).last
    assert_in_delta 0.3, chat.llm_params["temperature"]
    assert_equal 512, chat.llm_params["max_tokens"]
    assert_in_delta 0.9, chat.llm_params["top_p"]
  end

  test "create enqueues chat response job" do
    model = Model.find_by!(provider: "openai", model_id: "gemma-4-12b-it-vision-mtp")

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
    chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gemma-4-12b-it-vision-mtp"))

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
    chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gemma-4-12b-it-vision-mtp"))
    chat.messages.create!(role: :assistant, content: "### 見出し\n\n**太字**")

    get chat_path(chat)

    assert_response :success
    assert_select "#message_#{chat.messages.last.id}_content h3", text: "見出し"
    assert_select "#message_#{chat.messages.last.id}_content strong", text: "太字"
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
