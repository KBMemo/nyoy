# frozen_string_literal: true

class RenameSearxngConnectionToSearfront < ActiveRecord::Migration[8.1]
  class MigrationServiceConnection < ApplicationRecord
    self.table_name = "service_connections"
  end

  def up
    old = MigrationServiceConnection.find_by(key: "searxng")
    return unless old

    if MigrationServiceConnection.exists?(key: "searfront")
      old.destroy!
      return
    end

    old.update!(
      key: "searfront",
      name: old.name.to_s.include?("SearXNG") ? "searfront" : old.name,
      notes: "Chat web_search 用（searfront /v1/search）"
    )
  end

  def down
    current = MigrationServiceConnection.find_by(key: "searfront")
    return unless current
    return if MigrationServiceConnection.exists?(key: "searxng")

    current.update!(key: "searxng")
  end
end
