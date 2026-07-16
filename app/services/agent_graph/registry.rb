# frozen_string_literal: true

module AgentGraph
  module Registry
    Entry = Data.define(:graph_name, :runner, :failure_label, :approval_panel)

    module_function

    def entries
      @entries ||= [
        Entry.new(
          graph_name: ResearchGraph::NAME,
          runner: ResearchGraphRunner,
          failure_label: "Research Graph failed",
          approval_panel: nil
        ),
        Entry.new(
          graph_name: MemoWriteGraph::NAME,
          runner: MemoWriteGraphRunner,
          failure_label: "MemoWrite Graph failed",
          approval_panel: "chats/memo_write_approval"
        ),
        Entry.new(
          graph_name: MemoUpdateGraph::NAME,
          runner: MemoUpdateGraphRunner,
          failure_label: "MemoUpdate Graph failed",
          approval_panel: "chats/memo_write_approval"
        )
      ].freeze
    end

    def fetch(graph_name)
      entry = entries.find { |item| item.graph_name == graph_name.to_s }
      raise ArgumentError, "unknown agent graph: #{graph_name}" unless entry

      entry
    end

    def runner_for(graph_name)
      fetch(graph_name).runner
    end

    def failure_label_for(graph_name)
      fetch(graph_name).failure_label
    rescue ArgumentError
      "#{graph_name} Graph failed"
    end

    def approval_panel_for(graph_name)
      panel = fetch(graph_name).approval_panel
      raise ArgumentError, "approval panel is not supported for graph=#{graph_name}" if panel.blank?

      panel
    end

    def approval_graph_names
      entries.filter_map { |entry| entry.graph_name if entry.approval_panel.present? }
    end

    def approval_supported?(graph_name)
      approval_graph_names.include?(graph_name.to_s)
    end
  end
end
