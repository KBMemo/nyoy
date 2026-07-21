# frozen_string_literal: true

require "socket"

class LlamaServerAlertZabbixSender
  HEADER = "ZBXD\x01".b
  STATUS_VALUES = { "healthy" => 0, "warning" => 1, "failed" => 2 }.freeze

  class Error < StandardError; end

  def initialize(
    server: LlamaServerAlert.zabbix_server,
    port: LlamaServerAlert.zabbix_port,
    host: LlamaServerAlert.zabbix_host,
    key_prefix: LlamaServerAlert.zabbix_key_prefix,
    socket_factory: Socket
  )
    @server = server
    @port = port
    @host = host
    @key_prefix = key_prefix
    @socket_factory = socket_factory
    validate_configuration!
  end

  def deliver(reconciliation, policy: LlamaServerAlertPolicy.new(reconciliation))
    payload = LlamaServerAlertPayload.call(reconciliation, policy: policy)
    request = {
      request: "sender data",
      data: [
        item("#{@key_prefix}.status", STATUS_VALUES.fetch(reconciliation.status), reconciliation.checked_at),
        item("#{@key_prefix}.payload", JSON.generate(payload), reconciliation.checked_at)
      ]
    }
    response = exchange(JSON.generate(request))
    return if response["response"] == "success" && response.fetch("info", "").match?(/failed:\s*0\b/)

    raise Error, "Zabbix sender rejected alert: #{response.fetch('info', response['response'])}"
  rescue KeyError, JSON::ParserError => e
    raise Error, "Zabbix sender returned an invalid response: #{e.message}"
  rescue IOError, SocketError, SystemCallError => e
    raise Error, "Zabbix sender is unavailable: #{e.message}"
  end

  private

  def item(key, value, checked_at)
    { host: @host, key: key, value: value.to_s, clock: checked_at.to_i }
  end

  def exchange(body)
    frame = HEADER + [ body.bytesize ].pack("Q<") + body
    socket = @socket_factory.tcp(@server, @port, connect_timeout: 5)
    socket.write(frame)
    header = read_exact(socket, 13)
    raise Error, "Zabbix sender returned an invalid header" unless header.start_with?(HEADER)

    length = header.byteslice(5, 8).unpack1("Q<")
    JSON.parse(read_exact(socket, length))
  ensure
    socket&.close
  end

  def read_exact(socket, length)
    data = +"".b
    data << socket.readpartial(length - data.bytesize) while data.bytesize < length
    data
  rescue EOFError
    raise Error, "Zabbix sender closed the connection early"
  end

  def validate_configuration!
    raise Error, "Zabbix server is missing" if @server.blank?
    raise Error, "Zabbix host is missing" if @host.blank?
    raise Error, "Zabbix item key prefix is missing" if @key_prefix.blank?
    raise Error, "Zabbix port is invalid" unless @port.between?(1, 65_535)
  end
end
