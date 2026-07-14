# frozen_string_literal: true

class AddGoogleBingToSearxngEngines < ActiveRecord::Migration[8.0]
  class MigrationServiceConnection < ApplicationRecord
    self.table_name = "service_connections"
  end

  PREFERRED = %w[duckduckgo google bing wikipedia].freeze

  def up
    MigrationServiceConnection.where(key: "searxng").find_each do |connection|
      settings = connection.settings.is_a?(Hash) ? connection.settings.deep_dup : {}
      current = settings["engines"].to_s.split(",").map(&:strip).reject(&:blank?)
      merged = (current + (PREFERRED - current)).presence || PREFERRED
      settings["engines"] = merged.join(",")
      connection.update!(settings: settings)
    end
  end

  def down
    # keep engines (google/bing remain useful)
  end
end
