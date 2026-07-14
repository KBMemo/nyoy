# frozen_string_literal: true

class RemoveBingFromSearxngEngines < ActiveRecord::Migration[8.0]
  class MigrationServiceConnection < ApplicationRecord
    self.table_name = "service_connections"
  end

  def up
    MigrationServiceConnection.where(key: "searxng").find_each do |connection|
      settings = connection.settings.is_a?(Hash) ? connection.settings.deep_dup : {}
      engines = settings["engines"].to_s.split(",").map(&:strip).reject(&:blank?)
      next unless engines.include?("bing")

      engines.delete("bing")
      engines = %w[duckduckgo google wikipedia] if engines.empty?
      settings["engines"] = engines.join(",")
      connection.update!(settings: settings)
    end
  end

  def down
    # do not re-add bing
  end
end
