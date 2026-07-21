# frozen_string_literal: true

require "test_helper"

class LlamaServerAlertZabbixSenderTest < ActiveSupport::TestCase
  test "sends status and payload trapper items" do
    reconciliation = create_reconciliation("warning", findings: [ { "code" => "alias_drift" } ])
    socket = FakeSocket.new(success_response)
    factory = Object.new
    test = self
    factory.define_singleton_method(:tcp) do |server, port, connect_timeout:|
      test.assert_equal "bowmore", server
      test.assert_equal 10_051, port
      test.assert_equal 5, connect_timeout
      socket
    end

    sender = LlamaServerAlertZabbixSender.new(
      server: "bowmore", host: "nyoy-production", key_prefix: "nyoy.llama", socket_factory: factory
    )
    sender.deliver(reconciliation)

    request = socket.request
    assert_equal "sender data", request.fetch("request")
    status, payload = request.fetch("data")
    assert_equal({ "host" => "nyoy-production", "key" => "nyoy.llama.status", "value" => "1" },
                 status.slice("host", "key", "value"))
    assert_equal "llama_server.reconciliation.warning", JSON.parse(payload.fetch("value")).fetch("event")
    assert socket.closed?
  end

  test "raises when Zabbix rejects an item" do
    response = zabbix_frame(response: "success", info: "processed: 1; failed: 1; total: 2")
    sender = LlamaServerAlertZabbixSender.new(
      server: "bowmore", host: "nyoy-production", socket_factory: fake_factory(FakeSocket.new(response))
    )

    error = assert_raises(LlamaServerAlertZabbixSender::Error) do
      sender.deliver(create_reconciliation("failed"))
    end
    assert_match "failed: 1", error.message
  end

  private

  def create_reconciliation(status, findings: [])
    service_connections(:llama_switchd).llama_server_reconciliations.create!(
      status: status,
      findings: findings,
      checked_at: Time.current
    )
  end

  def success_response
    zabbix_frame(response: "success", info: "processed: 2; failed: 0; total: 2")
  end

  def zabbix_frame(payload)
    body = JSON.generate(payload)
    LlamaServerAlertZabbixSender::HEADER + [ body.bytesize ].pack("Q<") + body
  end

  def fake_factory(socket)
    Object.new.tap { |factory| factory.define_singleton_method(:tcp) { |*| socket } }
  end

  class FakeSocket
    attr_reader :written

    def initialize(response)
      @response = StringIO.new(response)
      @closed = false
    end

    def write(value)
      @written = value
    end

    def readpartial(length)
      value = @response.read(length)
      raise EOFError if value.blank?

      value
    end

    def close
      @closed = true
    end

    def closed?
      @closed
    end

    def request
      length = @written.byteslice(5, 8).unpack1("Q<")
      JSON.parse(@written.byteslice(13, length))
    end
  end
end
