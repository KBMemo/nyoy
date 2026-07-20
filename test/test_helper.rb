ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

LLAMA_SERVER_ADMIN_TEST_TOKEN = "test-llama-server-admin-token"
Rails.application.config.x.nyoy.llama_server_admin_token = LLAMA_SERVER_ADMIN_TEST_TOKEN

ORIGINAL_EMBEDDING_CLIENT_EMBED = EmbeddingClient.instance_method(:embed)

module LlamaServerAdminTestHelper
  def sign_in_llama_server_admin
    post llama_server_admin_session_path, params: { token: LLAMA_SERVER_ADMIN_TEST_TOKEN }
  end
end

ActionDispatch::IntegrationTest.include(LlamaServerAdminTestHelper)

module ActiveSupport
  class TestCase
    parallelize(workers: :number_of_processors)

    fixtures :all

    setup do
      EmbeddingClient.define_method(:embed) do |input:|
        text = Array(input).first.to_s
        seed = text.bytes.sum + text.length
        Array.new(Rails.application.config.x.nyoy.embedding_dimensions) do |index|
          Math.sin(seed + index)
        end
      end
    end
  end
end
