# frozen_string_literal: true

namespace :service_connections do
  desc "Report database references that still use ServiceConnection legacy keys"
  task legacy_key_audit: :environment do
    rows = ServiceConnectionLegacyKeyAudit.call
    puts JSON.pretty_generate(
      generated_at: Time.current.iso8601,
      legacy_connections: rows,
      database_clear: rows.all? { |row| row.fetch("database_clear") }
    )

    abort "Legacy ServiceConnection key references remain" if ENV["STRICT"] == "1" && rows.any? { |row| !row.fetch("database_clear") }
  end
end
