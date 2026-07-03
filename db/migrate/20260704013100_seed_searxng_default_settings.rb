# frozen_string_literal: true

class SeedSearxngDefaultSettings < ActiveRecord::Migration[8.0]
  class MigrationServiceConnection < ApplicationRecord
    self.table_name = "service_connections"
  end

  DEFAULTS = {
    "result_count" => 5,
    "concurrent_searches" => 1,
    "engines" => "duckduckgo,wikipedia",
    "retry_count" => 1,
    "max_searches_per_turn" => 2,
    "max_fetches_per_turn" => 3
  }.freeze

  def up
    MigrationServiceConnection.where(key: "searxng").find_each do |connection|
      next if connection.settings.is_a?(Hash) && connection.settings["engines"].present?

      connection.update!(settings: DEFAULTS)
    end
  end

  def down
    # keep settings
  end
end
