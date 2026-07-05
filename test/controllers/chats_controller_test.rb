# frozen_string_literal: true

require "base64"
require "test_helper"

class ChatsControllerTest < ActionDispatch::IntegrationTest
  setup do
    ChatModelCatalog.seed!
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
    assert_select "select[name='chat[model]'] option", minimum: 2
  end

  test "new syncs gpt-oss model when it was missing from models table" do
    Model.where(provider: "openai", model_id: "gpt-oss").delete_all

    get new_chat_path

    assert Model.exists?(provider: "openai", model_id: "gpt-oss")
    assert_select "select[name='chat[model]'] option", text: /GPT-OSS/
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

  test "show renders web tool limit form when searxng is enabled" do
    chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
    service_connections(:searxng).update!(enabled: true)

    get chat_path(chat)

    assert_response :success
    assert_select "input[name='max_searches_per_turn']"
    assert_select "input[name='max_fetches_per_turn']"
  end

  test "update_web_tool_limits persists searxng settings" do
    chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
    connection = service_connections(:searxng)

    patch web_tool_limits_chat_path(chat), params: {
      max_searches_per_turn: 4,
      max_fetches_per_turn: 6
    }

    assert_redirected_to chat_path(chat)
    settings = connection.reload.searxng_settings
    assert_equal 4, settings.max_searches_per_turn
    assert_equal 6, settings.max_fetches_per_turn
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
      thinking_elapsed_ms: 4567
    )

    get chat_path(chat)

    assert_response :success
    assert_select "#message_#{message.id} .nyoy-chat-message-stat", minimum: 3
    assert_select "#message_#{message.id} .nyoy-chat-message-stat dd", text: "GPT-OSS"
    assert_select "#message_#{message.id} .nyoy-chat-message-stat dd", text: "12.3秒"
    assert_select "#message_#{message.id} .nyoy-chat-message-stat dd", text: "4.6秒"
  end
end
