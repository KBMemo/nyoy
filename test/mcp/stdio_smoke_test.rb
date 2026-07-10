# frozen_string_literal: true

require "test_helper"
require "open3"
require "json"

class McpStdioSmokeTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
    NyoyConnectionStore.clear_cache!
    ChatTools::Registry.reset_client!
    @original_token = Rails.application.config.x.nyoy.mcp_api_token
    Rails.application.config.x.nyoy.mcp_api_token = "test-mcp-token"
  end

  teardown do
    Rails.application.config.x.nyoy.mcp_api_token = @original_token
    ChatTools::Registry.reset_client!
  end

  test "stdio transport responds to initialize" do
    script = Rails.root.join("bin/mcp-stdio").to_s
    env = ENV.to_h.merge(
      "RAILS_ENV" => "test",
      "MCP_API_TOKEN" => "test-mcp-token"
    )

    Open3.popen3(env, script, chdir: Rails.root.to_s) do |stdin, stdout, stderr, wait_thr|
      stdin.puts(initialize_payload.to_json)
      stdin.flush

      response_line = read_json_line(stdout, timeout: 30)
      stderr_text = stderr.read_nonblock(4096) rescue ""
      assert response_line.present?, "no response on stdout (stderr: #{stderr_text})"

      response = JSON.parse(response_line)
      assert_equal "nyoy", response.dig("result", "serverInfo", "name")
    ensure
      stdin&.close
      terminate_process(wait_thr)
    end
  end

  private

  def initialize_payload
    {
      jsonrpc: "2.0",
      id: 1,
      method: "initialize",
      params: {
        protocolVersion: "2025-03-26",
        capabilities: {},
        clientInfo: { name: "test", version: "0.1.0" }
      }
    }
  end

  def read_json_line(io, timeout:)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout

    loop do
      if io.wait_readable(0.1)
        line = io.gets
        return line&.strip if line.present?
      end

      return nil if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
    end
  end

  def terminate_process(wait_thr)
    return unless wait_thr&.alive?

    Process.kill("TERM", wait_thr.pid)
    wait_thr.join(2)
    Process.kill("KILL", wait_thr.pid) if wait_thr.alive?
  rescue Errno::ESRCH
    nil
  end
end
