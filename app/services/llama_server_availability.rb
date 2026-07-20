# frozen_string_literal: true

class LlamaServerAvailability
  def self.available?(connection, max_age: Rails.application.config.x.nyoy.llama_server_availability_max_age)
    new(connection, max_age: max_age).available?
  end

  def initialize(connection, max_age:)
    @connection = connection
    @max_age = max_age
  end

  def available?
    return true if @connection.managed_server_id.blank? || @connection.manager_connection.nil?

    reconciliation = @connection.manager_connection.llama_server_reconciliations
      .where(status: %w[healthy warning])
      .recent
      .first
    return true unless reconciliation
    return true if reconciliation.checked_at < @max_age.seconds.ago

    server = reconciliation.server_snapshot.find { |item| item["id"] == @connection.managed_server_id }
    server.present? && server["ready"] == true
  end
end
