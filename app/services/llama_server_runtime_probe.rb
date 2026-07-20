# frozen_string_literal: true

class LlamaServerRuntimeProbe
  Result = Struct.new(:server_id, :model_alias, :model_path, :total_slots, :error, keyword_init: true)

  def initialize(control_url:, client_factory: nil)
    @control_uri = URI.parse(control_url)
    @client_factory = client_factory || ->(base_url) { LlamaCppClient.new(base_url: base_url) }
  end

  def call(servers)
    servers.filter_map do |server|
      next unless server["ready"]

      result = probe(server)
      [ server["id"], result ]
    end.to_h
  end

  private

  def probe(server)
    props = @client_factory.call(data_plane_url(server.fetch("port"))).props
    Result.new(
      server_id: server["id"],
      model_alias: props["model_alias"],
      model_path: props["model_path"],
      total_slots: positive_integer(props["total_slots"])
    )
  rescue LlamaCppClient::Error, KeyError, ArgumentError, TypeError => e
    Result.new(server_id: server["id"], error: e.message)
  end

  def data_plane_url(port)
    uri = @control_uri.dup
    uri.port = Integer(port)
    uri.path = ""
    uri.query = nil
    uri.fragment = nil
    uri.to_s.sub(%r{/\z}, "")
  end

  def positive_integer(value)
    number = Integer(value)
    number.positive? ? number : nil
  rescue ArgumentError, TypeError
    nil
  end
end
