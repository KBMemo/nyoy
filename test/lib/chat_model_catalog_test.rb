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
end
