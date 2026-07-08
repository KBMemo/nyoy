# frozen_string_literal: true

require "test_helper"

class ChatModelCatalogTest < ActiveSupport::TestCase
  test "definitions come from enabled chat connections" do
    definitions = ChatModelCatalog.definitions

    assert_equal 2, definitions.length
    assert_equal "gemma-4-12b-it-vision-mtp", definitions.find { |d| d.connection_key == "llama_cpp" }.model_id
    assert_equal "gpt-oss", definitions.find { |d| d.connection_key == "gpt_oss" }.model_id
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

  test "default_model follows app setting connection key" do
    ChatModelCatalog.seed!
    AppSetting.delete_all
    AppSetting.instance.update!(default_chat_connection_key: "gpt_oss")

    model = ChatModelCatalog.default_model

    assert_equal "gpt-oss", model.model_id
  ensure
    AppSetting.delete_all
  end

  test "grouped_model_options groups models by connection name" do
    ChatModelCatalog.seed!

    groups = ChatModelCatalog.grouped_model_options
    labels = groups.map(&:first)

    assert_includes labels, "Gemma Vision"
    assert_includes labels, "GPT-OSS"

    gemma_options = groups.find { |label, _| label == "Gemma Vision" }.last
    gpt_oss_options = groups.find { |label, _| label == "GPT-OSS" }.last

    assert_equal [ "gemma-4-12b-it-vision-mtp" ], gemma_options.map(&:first)
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
