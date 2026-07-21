# frozen_string_literal: true

namespace :llm_usages do
  desc "Audit LLM usage assignments, model capabilities, and connection availability"
  task audit: :environment do
    rows = LlmUsageAssignmentAudit.call
    healthy = rows.all? { |row| row.fetch("status") == "healthy" }
    puts JSON.pretty_generate(
      generated_at: Time.current.iso8601,
      usages: rows,
      healthy: healthy
    )

    abort "LLM usage assignments are not healthy" if ENV["STRICT"] == "1" && !healthy
  end
end
