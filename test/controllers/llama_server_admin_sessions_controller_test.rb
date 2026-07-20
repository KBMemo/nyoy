# frozen_string_literal: true

require "test_helper"

class LlamaServerAdminSessionsControllerTest < ActionDispatch::IntegrationTest
  test "redirects unauthenticated management request to sign in" do
    get service_connections_path

    assert_redirected_to new_llama_server_admin_session_path
  end

  test "signs in and returns to requested management page" do
    get service_connections_path
    post llama_server_admin_session_path, params: { token: LLAMA_SERVER_ADMIN_TEST_TOKEN }

    assert_redirected_to service_connections_path
    follow_redirect!
    assert_response :success
  end

  test "rejects an invalid token" do
    post llama_server_admin_session_path, params: { token: "invalid" }

    assert_response :unprocessable_entity
    assert_select "input#current-password[required][autocomplete='current-password']"
    assert_match "管理トークンが一致しません", response.body
  end

  test "signs out" do
    sign_in_llama_server_admin
    delete llama_server_admin_session_path
    get service_connections_path

    assert_redirected_to new_llama_server_admin_session_path
  end
end
