# frozen_string_literal: true

module AgentGraph
  module Registry
    Entry = Data.define(
      :graph_name,
      :graph_class,
      :runner,
      :summary_class,
      :failure_label,
      :approval_panel,
      :approval_copy,
      :approve_notice,
      :reject_notice,
      :supersede_reason,
      :resume_tool
    )

    ApprovalCopy = Data.define(:status_label, :description, :approve_label, :reject_confirm)

    module_function

    def entries
      ensure_defaults!
      @entries.values
    end

    def register(
      key:,
      graph:,
      runner:,
      summary:,
      failure_label: nil,
      approval_panel: nil,
      approval_copy: nil,
      approve_notice: nil,
      reject_notice: nil,
      supersede_reason: nil,
      resume_tool: nil
    )
      entry = Entry.new(
        graph_name: key.to_s,
        graph_class: graph,
        runner: runner,
        summary_class: summary,
        failure_label: failure_label || "#{key} Graph failed",
        approval_panel: approval_panel,
        approval_copy: approval_copy,
        approve_notice: approve_notice,
        reject_notice: reject_notice,
        supersede_reason: supersede_reason,
        resume_tool: resume_tool
      )
      registry[entry.graph_name] = entry
      entry
    end

    def reset!
      @entries = {}
      @defaults_registered = false
    end

    def fetch(graph_name)
      entry = entries.find { |item| item.graph_name == graph_name.to_s }
      raise ArgumentError, "unknown agent graph: #{graph_name}" unless entry

      entry
    end

    def runner_for(graph_name)
      fetch(graph_name).runner
    end

    def graph_for(graph_name)
      entry = fetch(graph_name)
      graph = entry.graph_class.new
      raise ArgumentError, "registered graph name mismatch: #{entry.graph_name} != #{graph.name}" if graph.name != entry.graph_name

      graph
    end

    def supersede_reason_for(graph_name)
      fetch(graph_name).supersede_reason
    end

    def summary_for(graph_name)
      fetch(graph_name).summary_class
    end

    def resume_tool_for(graph_name)
      fetch(graph_name).resume_tool
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

    def approval_copy_for(graph_name)
      copy = fetch(graph_name).approval_copy
      raise ArgumentError, "approval copy is not supported for graph=#{graph_name}" unless copy

      copy
    end

    def approve_notice_for(graph_name)
      notice = fetch(graph_name).approve_notice
      raise ArgumentError, "approval notice is not supported for graph=#{graph_name}" if notice.blank?

      notice
    end

    def reject_notice_for(graph_name)
      notice = fetch(graph_name).reject_notice
      raise ArgumentError, "rejection notice is not supported for graph=#{graph_name}" if notice.blank?

      notice
    end

    def approval_graph_names
      entries.filter_map { |entry| entry.graph_name if entry.approval_panel.present? }
    end

    def approval_supported?(graph_name)
      approval_graph_names.include?(graph_name.to_s)
    end

    def registry
      @entries ||= {}
    end
    private_class_method :registry

    def ensure_defaults!
      return if @defaults_registered

      register_defaults!
      @defaults_registered = true
    end
    private_class_method :ensure_defaults!

    def register_defaults!
      register(
        key: ResearchGraph::NAME,
        graph: ResearchGraph,
        runner: ResearchGraphRunner,
        summary: ResearchRunSummary,
        failure_label: "Research Graph failed",
        supersede_reason: "superseded by a newer research run"
      )
      register(
        key: ImageUnderstandingGraph::NAME,
        graph: ImageUnderstandingGraph,
        runner: ImageUnderstandingGraphRunner,
        summary: ImageUnderstandingRunSummary,
        failure_label: "ImageUnderstanding Graph failed",
        supersede_reason: "superseded by a newer image understanding run"
      )
      register(
        key: DiagnosticGraph::NAME,
        graph: DiagnosticGraph,
        runner: DiagnosticGraphRunner,
        summary: DiagnosticRunSummary,
        failure_label: "Diagnostic Graph failed",
        supersede_reason: "superseded by a newer diagnostic run"
      )
      register(
        key: MemoWriteGraph::NAME,
        graph: MemoWriteGraph,
        runner: MemoWriteGraphRunner,
        summary: MemoWriteRunSummary,
        failure_label: "MemoWrite Graph failed",
        approval_panel: "chats/memo_write_approval",
        approval_copy: ApprovalCopy.new(
          status_label: "MemoWrite",
          description: "内容を確認してから徒然に新規保存してください。",
          approve_label: "この内容で徒然に保存する",
          reject_confirm: "このメモ保存を却下しますか？"
        ),
        approve_notice: "メモ草案を承認しました。徒然へ保存します。",
        reject_notice: "メモ保存を却下しました。",
        supersede_reason: "superseded by a newer memo write run",
        resume_tool: "resume_memo_write_graph"
      )
      register(
        key: MemoUpdateGraph::NAME,
        graph: MemoUpdateGraph,
        runner: MemoUpdateGraphRunner,
        summary: MemoUpdateRunSummary,
        failure_label: "MemoUpdate Graph failed",
        approval_panel: "chats/memo_write_approval",
        approval_copy: ApprovalCopy.new(
          status_label: "MemoUpdate",
          description: "内容を確認してから既存メモへ反映してください。",
          approve_label: "この内容で徒然メモを更新する",
          reject_confirm: "このメモ更新を却下しますか？"
        ),
        approve_notice: "メモ更新を承認しました。徒然へ反映します。",
        reject_notice: "メモ更新を却下しました。",
        supersede_reason: "superseded by a newer memo update run",
        resume_tool: "resume_memo_update_graph"
      )
    end
    private_class_method :register_defaults!
  end
end
