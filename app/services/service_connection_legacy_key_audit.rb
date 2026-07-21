# frozen_string_literal: true

class ServiceConnectionLegacyKeyAudit
  REFERENCE_COLUMNS = {
    "app_settings" => %w[default_chat_connection_key default_style_plan_connection_key],
    "image_generations" => %w[style_plan_connection_key],
    "img2img_generations" => %w[style_plan_connection_key],
    "memo_illustrations" => %w[style_plan_connection_key]
  }.freeze

  class << self
    def call
      ServiceConnection.where.not(legacy_key: nil).order(:id).map do |connection|
        references = column_references(connection.legacy_key)
        model_count = Model.where("metadata ->> 'connection_key' = ?", connection.legacy_key).count
        references["models.metadata.connection_key"] = model_count if model_count.positive?

        {
          "key" => connection.key,
          "legacy_key" => connection.legacy_key,
          "references" => references,
          "reference_count" => references.values.sum,
          "database_clear" => references.empty?
        }
      end
    end

    private

    def column_references(legacy_key)
      REFERENCE_COLUMNS.each_with_object({}) do |(table, columns), references|
        columns.each do |column|
          count = count_rows(table, column, legacy_key)
          references["#{table}.#{column}"] = count if count.positive?
        end
      end
    end

    def count_rows(table, column, value)
      connection = ActiveRecord::Base.connection
      sql = <<~SQL.squish
        SELECT COUNT(*)
        FROM #{connection.quote_table_name(table)}
        WHERE #{connection.quote_column_name(column)} = #{connection.quote(value)}
      SQL
      connection.select_value(sql).to_i
    end
  end
end
