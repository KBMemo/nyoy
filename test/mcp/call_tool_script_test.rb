# frozen_string_literal: true

require "test_helper"
require "json"
require "open3"
require "socket"

class McpCallToolScriptTest < ActiveSupport::TestCase
  setup do
    @server = TCPServer.new("127.0.0.1", 0)
    @requests = Queue.new
    @thread = Thread.new { serve_requests(2) }
    @url = "http://127.0.0.1:#{@server.addr[1]}/mcp"
  end

  teardown do
    @server.close
    @thread.join(2)
  end

  test "expands tool text payload by default" do
    stdout, stderr, status = run_script("run_image_understanding_graph", '{"question":"説明して"}')

    assert status.success?, stderr
    payload = JSON.parse(stdout)
    request = @requests.pop

    assert_equal 123, payload["agent_run_id"]
    assert_equal "completed", payload["status"]
    assert_equal "Bearer test-token", request[:authorization]
    assert_equal "tools/call", request.dig(:body, "method")
    assert_equal "run_image_understanding_graph", request.dig(:body, "params", "name")
    assert_equal "説明して", request.dig(:body, "params", "arguments", "question")
  end

  test "raw option prints outer json rpc response" do
    stdout, stderr, status = run_script("--raw", "run_image_understanding_graph", "{}")

    assert status.success?, stderr
    payload = JSON.parse(stdout)

    assert_equal "123", JSON.parse(payload.dig("result", "content", 0, "text"))["agent_run_id"].to_s
  end

  test "requires tool name" do
    stdout, stderr, status = run_script_without_token

    assert_not status.success?
    assert_empty stdout
    assert_includes stderr, "Usage: bin/mcp-call-tool"
  end

  test "requires mcp token" do
    stdout, stderr, status = run_script_without_token("run_image_understanding_graph", "{}")

    assert_not status.success?
    assert_empty stdout
    assert_includes stderr, "MCP_API_TOKEN is required"
  end

  test "requires json object arguments" do
    stdout, stderr, status = run_script("run_image_understanding_graph", "[]")

    assert_not status.success?
    assert_empty stdout
    assert_includes stderr, "JSON_ARGUMENTS must be a JSON object"
  end

  private

  def run_script(*args)
    env = {
      "NYOY_MCP_URL" => @url,
      "MCP_API_TOKEN" => "test-token"
    }
    Open3.capture3(env, Rails.root.join("bin/mcp-call-tool").to_s, *args, chdir: Rails.root.to_s)
  end

  def run_script_without_token(*args)
    env = {
      "NYOY_MCP_URL" => @url
    }
    Open3.capture3(env, Rails.root.join("bin/mcp-call-tool").to_s, *args, chdir: Rails.root.to_s)
  end

  def serve_requests(limit)
    limit.times do
      socket = @server.accept
      raw_request = read_http_request(socket)
      headers, body = parse_http_request(raw_request)
      @requests << {
        authorization: headers["authorization"],
        body: JSON.parse(body)
      }
      response_body = JSON.generate(
        result: {
          content: [
            {
              type: "text",
              text: JSON.generate(agent_run_id: 123, status: "completed")
            }
          ]
        }
      )
      socket.write "HTTP/1.1 200 OK\r\n"
      socket.write "Content-Type: application/json\r\n"
      socket.write "Content-Length: #{response_body.bytesize}\r\n"
      socket.write "Connection: close\r\n"
      socket.write "\r\n"
      socket.write response_body
      socket.close
    end
  rescue IOError
    nil
  end

  def read_http_request(socket)
    buffer = +""
    loop do
      buffer << socket.readpartial(1024)
      header, body = buffer.split("\r\n\r\n", 2)
      next unless body

      length = header.each_line.find { |line| line.downcase.start_with?("content-length:") }
        &.split(":", 2)
        &.last
        .to_i
      return buffer if body.bytesize >= length
    end
  end

  def parse_http_request(raw_request)
    header, body = raw_request.split("\r\n\r\n", 2)
    headers = header.each_line.drop(1).each_with_object({}) do |line, memo|
      key, value = line.split(":", 2)
      memo[key.downcase] = value.to_s.strip if key
    end
    [ headers, body.to_s ]
  end
end
