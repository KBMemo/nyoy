# frozen_string_literal: true

module Mcp
  module AgentGraphResponse
    module_function

    def success(run, summary:, resume_tool: nil)
      payload = summary.build(run)
      if resume_tool && run.awaiting_approval?
        payload[:note] = "draft を確認し #{resume_tool}(agent_run_id, decision) で続行してください。"
      end

      MCP::Tool::Response.new([{ type: "text", text: JSON.generate(payload) }])
    end

    def error(message)
      MCP::Tool::Response.new(
        [{ type: "text", text: JSON.generate({ error: message }) }],
        error: true
      )
    end

    def find_run(agent_run_id, graph_name:)
      AgentRun.find_by(id: agent_run_id, graph_name: graph_name)
    end

    def find_run_or_error(agent_run_id, graph_name:)
      run = find_run(agent_run_id, graph_name: graph_name)
      return [ run, nil ] if run

      [ nil, missing_run(agent_run_id) ]
    end

    def awaiting_run_or_error(agent_run_id, graph_name:)
      run, response = find_run_or_error(agent_run_id, graph_name: graph_name)
      return [ nil, response ] if response
      return [ run, nil ] if run.awaiting_approval?

      [ nil, not_awaiting_approval(run) ]
    end

    def missing_run(agent_run_id)
      error("AgentRun #{agent_run_id} が見つかりません")
    end

    def not_awaiting_approval(run)
      error("承認待ちではありません（status=#{run.status}）")
    end
  end
end
