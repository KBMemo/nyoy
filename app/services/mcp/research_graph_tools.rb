# frozen_string_literal: true

module Mcp
  # MCP-only Research Graph tools (not exposed to the Chat tool loop).
  module ResearchGraphTools
    module_function

    def mcp_tools
      [
        run_research_graph_tool,
        get_research_graph_tool,
        resume_research_graph_tool
      ]
    end

    def run_research_graph_tool
      MCP::Tool.define(
        name: "run_research_graph",
        description: <<~TEXT.squish,
          Research Graph で調査する（メモ想起→Web 検索→URL 取得→ドラフト合成→回答）。
          plan.sensitive（保存・公開・確認してから 等）のときだけ承認待ちになる。
          auto_approve=true（既定）なら sensitive でも承認をスキップする。
          awaiting_approval のときは draft を確認して resume_research_graph を呼ぶ。
        TEXT
        input_schema: {
          type: "object",
          properties: {
            question: { type: "string", description: "調査したい質問" },
            chat_id: {
              type: "integer",
              description: "既存 Chat id。省略時は MCP 用チャットを新規作成"
            },
            auto_approve: {
              type: "boolean",
              description: "true（既定）ならドラフト承認を自動で通す。false なら承認待ち"
            }
          },
          required: [ "question" ]
        },
        annotations: {
          read_only_hint: false,
          destructive_hint: false,
          idempotent_hint: false,
          open_world_hint: true
        }
      ) do |question:, chat_id: nil, auto_approve: true, **|
        auto = auto_approve.nil? ? true : ActiveModel::Type::Boolean.new.cast(auto_approve)
        run = AgentGraph::ResearchGraphRunner.call_for_mcp(
          question: question,
          chat_id: chat_id,
          auto_approve: auto
        )
        Mcp::ResearchGraphTools.success_response(run)
      rescue ArgumentError => e
        Mcp::ResearchGraphTools.error_response(e.message)
      rescue StandardError => e
        Rails.logger.error("run_research_graph failed: #{e.full_message}")
        Mcp::ResearchGraphTools.error_response(e.message)
      end
    end

    def get_research_graph_tool
      MCP::Tool.define(
        name: "get_research_graph",
        description: "run_research_graph / resume_research_graph の実行状態とドラフト・最終回答を取得する。",
        input_schema: {
          type: "object",
          properties: {
            agent_run_id: { type: "integer", description: "AgentRun の id" }
          },
          required: [ "agent_run_id" ]
        },
        annotations: {
          read_only_hint: true,
          destructive_hint: false,
          idempotent_hint: true,
          open_world_hint: false
        }
      ) do |agent_run_id:, **|
        run = AgentRun.find_by(id: agent_run_id, graph_name: AgentGraph::ResearchGraph::NAME)
        unless run
          return Mcp::ResearchGraphTools.error_response("AgentRun #{agent_run_id} が見つかりません")
        end

        Mcp::ResearchGraphTools.success_response(run)
      end
    end

    def resume_research_graph_tool
      MCP::Tool.define(
        name: "resume_research_graph",
        description: "awaiting_approval の Research Graph を承認または却下して再開する。",
        input_schema: {
          type: "object",
          properties: {
            agent_run_id: { type: "integer", description: "AgentRun の id" },
            decision: {
              type: "string",
              enum: %w[approved rejected],
              description: "approved で最終回答へ / rejected で却下"
            }
          },
          required: %w[agent_run_id decision]
        },
        annotations: {
          read_only_hint: false,
          destructive_hint: false,
          idempotent_hint: false,
          open_world_hint: false
        }
      ) do |agent_run_id:, decision:, **|
        run = AgentRun.find_by(id: agent_run_id, graph_name: AgentGraph::ResearchGraph::NAME)
        unless run
          return Mcp::ResearchGraphTools.error_response("AgentRun #{agent_run_id} が見つかりません")
        end
        unless run.awaiting_approval?
          return Mcp::ResearchGraphTools.error_response(
            "承認待ちではありません（status=#{run.status}）"
          )
        end

        completed = AgentGraph::ResearchGraphRunner.resume(run, decision: decision)
        Mcp::ResearchGraphTools.success_response(completed)
      rescue ArgumentError => e
        Mcp::ResearchGraphTools.error_response(e.message)
      rescue StandardError => e
        Rails.logger.error("resume_research_graph failed: #{e.full_message}")
        Mcp::ResearchGraphTools.error_response(e.message)
      end
    end

    def success_response(run)
      payload = AgentGraph::ResearchGraphRunner.summary_for(run)
      if run.awaiting_approval?
        payload[:note] = "draft を確認し resume_research_graph(agent_run_id, decision) で続行してください。"
      end
      MCP::Tool::Response.new([{ type: "text", text: JSON.generate(payload) }])
    end

    def error_response(message)
      MCP::Tool::Response.new(
        [{ type: "text", text: JSON.generate({ error: message }) }],
        error: true
      )
    end
  end
end
