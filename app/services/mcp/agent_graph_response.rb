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
  end
end
