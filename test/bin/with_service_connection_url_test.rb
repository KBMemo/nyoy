# frozen_string_literal: true

require "test_helper"
require "open3"
require "rbconfig"

class WithServiceConnectionUrlTest < ActiveSupport::TestCase
  setup do
    @connection = service_connections(:vision_llama)
    @original_url = @connection.base_url
  end

  teardown do
    @connection.update!(base_url: @original_url)
  end

  test "temporarily changes url while command succeeds and restores it" do
    stdout, stderr, status = run_script(RbConfig.ruby, "-e", "exit 0")

    assert status.success?, stderr
    assert_empty stdout
    assert_includes stderr, "vision_llama base_url temporarily set to http://127.0.0.1:9"
    assert_includes stderr, "vision_llama base_url restored to #{@original_url}"
    assert_equal @original_url, @connection.reload.base_url
  end

  test "restores url and preserves command failure status" do
    _stdout, stderr, status = run_script(RbConfig.ruby, "-e", "exit 7")

    assert_equal 7, status.exitstatus
    assert_includes stderr, "vision_llama base_url restored to #{@original_url}"
    assert_equal @original_url, @connection.reload.base_url
  end

  private

  def run_script(*command)
    env = { "RAILS_ENV" => "test" }
    Open3.capture3(
      env,
      Rails.root.join("bin/with-service-connection-url").to_s,
      "vision_llama",
      "http://127.0.0.1:9",
      "--",
      *command,
      chdir: Rails.root.to_s
    )
  end
end
