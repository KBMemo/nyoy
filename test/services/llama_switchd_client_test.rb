# frozen_string_literal: true

require "test_helper"

class LlamaSwitchdClientTest < ActiveSupport::TestCase
  test "lists servers with bearer authentication" do
    response = json_response("200", { ok: true, servers: [ { id: "main", port: 10010 } ] })
    request = nil

    with_http_response(response) do |http|
      http.define_singleton_method(:request) do |incoming|
        request = incoming
        response
      end

      servers = client.list_servers
      assert_equal "main", servers.first["id"]
    end

    assert_equal "Bearer secret", request["Authorization"]
    assert_equal "/v1/servers", request.uri.path
  end

  test "health does not send bearer authentication" do
    response = json_response("200", { ok: true, service: "llama-switchd" })
    request = nil

    with_http_response(response) do |http|
      http.define_singleton_method(:request) do |incoming|
        request = incoming
        response
      end
      client.health
    end

    assert_nil request["Authorization"]
  end

  test "gets escaped server id" do
    response = json_response("200", { ok: true, server: { id: "main model" }, values: {} })
    request = nil

    with_http_response(response) do |http|
      http.define_singleton_method(:request) do |incoming|
        request = incoming
        response
      end
      client.get_server("main model")
    end

    assert_equal "/v1/servers/main%20model", request.uri.path
  end

  test "posts lifecycle action" do
    response = json_response("200", { ok: true })
    request = nil

    with_http_response(response) do |http|
      http.define_singleton_method(:request) do |incoming|
        request = incoming
        response
      end
      client.restart_server("main")
    end

    assert_instance_of Net::HTTP::Post, request
    assert_equal "/v1/servers/main/restart", request.uri.path
  end

  test "raises typed error for upstream failure" do
    response = json_response("401", { ok: false, error: "unauthorized" })

    error = assert_raises(LlamaSwitchdClient::Error) do
      with_http_response(response) { client.list_models }
    end

    assert_equal 401, error.status
    assert_match(/unauthorized/, error.message)
  end

  test "requires api token" do
    error = assert_raises(LlamaSwitchdClient::Error) do
      LlamaSwitchdClient.new(base_url: "http://switchd.test:11335", api_token: nil)
    end

    assert_match(/トークン/, error.message)
  end

  private

  def client
    LlamaSwitchdClient.new(base_url: "http://switchd.test:11335", api_token: "secret")
  end

  def with_http_response(response)
    http = Object.new
    http.define_singleton_method(:use_ssl=) { |_| }
    http.define_singleton_method(:open_timeout=) { |_| }
    http.define_singleton_method(:read_timeout=) { |_| }
    http.define_singleton_method(:request) { |_| response }
    original = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) { |*| http }
    yield http
  ensure
    Net::HTTP.define_singleton_method(:new, original)
  end

  def json_response(code, body)
    klass = code.to_i.between?(200, 299) ? Net::HTTPOK : Net::HTTPUnauthorized
    klass.new("1.1", code, "response").tap do |response|
      response.instance_variable_set(:@read, true)
      response.body = JSON.generate(body)
    end
  end
end
