# frozen_string_literal: true

require "test_helper"

class ChatModelCatalogTest < ActiveSupport::TestCase
  test "definitions come from enabled generative model endpoints" do
    definitions = ChatModelCatalog.definitions

    assert_equal 3, definitions.length
    assert_equal "gemma-4-e4b-it-qat-ud-q4-k-xl", definitions.find { |d| d.connection_key == "llama_cpp" }.model_id
    assert_equal "gpt-oss", definitions.find { |d| d.connection_key == "gpt_oss" }.model_id
    assert_equal "qwen3vl-4b-instruct-q4-k-m", definitions.find { |d| d.connection_key == "vision_llama" }.model_id
  end

  test "definitions exclude bound server that is not ready" do
    connection = service_connections(:llama_cpp)
    manager = service_connections(:llama_switchd)
    connection.update!(manager_connection: manager, managed_server_id: "main")
    manager.llama_server_reconciliations.create!(
      status: "warning",
      server_snapshot: [ { "id" => "main", "ready" => false } ],
      checked_at: Time.current
    )

    assert_not_includes ChatModelCatalog.definitions.map(&:connection_key), "llama_cpp"
    assert_includes ChatModelCatalog.configured_definitions.map(&:connection_key), "llama_cpp"
  end

  test "context_for uses connection store url" do
    ChatModelCatalog.seed!
    model = Model.find_by!(provider: "openai", model_id: "gpt-oss")

    context = ChatModelCatalog.context_for(model)

    assert_equal "http://balvenie:10010/v1", context.config.openai_api_base
    assert_equal "local", context.config.openai_api_key
  end

  test "context_for uses openai api key from connection store" do
    connection = service_connections(:openai)
    connection.update!(enabled: true, api_token: "sk-test-key", server_model: "gpt-4o-mini", settings: { "chat_models" => %w[gpt-4o-mini] })
    ChatModelCatalog.seed!

    model = Model.find_by!(provider: "openai", model_id: "gpt-4o-mini")
    context = ChatModelCatalog.context_for(model)

    assert_equal "https://api.openai.com/v1", context.config.openai_api_base
    assert_equal "sk-test-key", context.config.openai_api_key
  end

  test "definitions include multiple openai chat models" do
    connection = service_connections(:openai)
    connection.update!(
      enabled: true,
      api_token: "sk-test-key",
      settings: { "chat_models" => %w[gpt-4o gpt-4o-mini] }
    )

    definitions = ChatModelCatalog.definitions

    assert_includes definitions.map(&:model_id), "gpt-4o"
    assert_includes definitions.map(&:model_id), "gpt-4o-mini"
  end

  test "default_model follows chat usage assignment" do
    ChatModelCatalog.seed!
    LlmUsageAssignment.delete_all
    model = Model.find_by!(provider: "openai", model_id: "gpt-oss")
    LlmUsageAssignment.create!(usage_key: "chat.default", model: model)

    default_model = ChatModelCatalog.default_model

    assert_equal "gpt-oss", default_model.model_id
  end

  test "grouped_model_options groups models by connection name" do
    ChatModelCatalog.seed!

    groups = ChatModelCatalog.grouped_model_options
    labels = groups.map(&:first)

    assert_includes labels, "Gemma 4 E4B"
    assert_includes labels, "GPT-OSS"

    gemma_options = groups.find { |label, _| label == "Gemma 4 E4B" }.last
    gpt_oss_options = groups.find { |label, _| label == "GPT-OSS" }.last

    assert_equal [ "gemma-4-e4b-it-qat-ud-q4-k-xl" ], gemma_options.map(&:first)
    assert_equal [ "gpt-oss" ], gpt_oss_options.map(&:first)
  end

  test "grouped_model_options groups multiple openai models under one connection" do
    connection = service_connections(:openai)
    connection.update!(
      enabled: true,
      api_token: "sk-test-key",
      settings: { "chat_models" => %w[gpt-4o gpt-4o-mini] }
    )
    ChatModelCatalog.seed!

    groups = ChatModelCatalog.grouped_model_options
    openai_group = groups.find { |label, _| label == "OpenAI（ChatGPT）" }

    assert_equal %w[gpt-4o gpt-4o-mini], openai_group.last.map(&:first)
  end
end
