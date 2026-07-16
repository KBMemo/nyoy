# frozen_string_literal: true

module ChatTools
  module MainLlmToolPolicy
    READ_ONLY_TOOL_NAMES = %w[
      search_memos
      get_memo
      recall_memos
      web_search
      fetch_url
      search_fetched_page
      analyze_image
      list_albums
      get_media
      list_sampling_presets
    ].freeze

    WRITE_TOOL_NAMES = %w[
      create_memo
      update_memo
      apply_sampling_preset
    ].freeze

    module_function

    def filter(tool_classes)
      classes = Array(tool_classes)
      allowed = allowed_tool_names
      return classes if allowed == :all

      classes.select { |tool_class| allowed.include?(tool_name(tool_class)) }
    end

    def mode
      Rails.application.config.x.nyoy.main_llm_tool_mode.to_s.presence || "restricted"
    end

    def allowed_tool_names
      allowlist = explicit_allowlist
      return allowlist if allowlist.any?

      case mode
      when "all"
        :all
      when "none", "off", "false"
        []
      else
        READ_ONLY_TOOL_NAMES
      end
    end

    def write_tool?(tool_name)
      WRITE_TOOL_NAMES.include?(tool_name.to_s)
    end

    def tool_name(tool_class)
      tool_class.new.name
    end

    def explicit_allowlist
      Array(Rails.application.config.x.nyoy.main_llm_tool_allowlist)
        .flat_map { |value| value.to_s.split(",") }
        .map(&:strip)
        .reject(&:empty?)
    end
  end
end
