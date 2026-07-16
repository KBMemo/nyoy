# frozen_string_literal: true

module Mcp
  # MCP-only Research Graph tools (not exposed to the Chat tool loop).
  module ResearchGraphTools
    GRAPH_NAME = AgentGraph::ResearchGraph::NAME

    module_function

    def mcp_tools
      [
        run_research_graph_tool,
        get_research_graph_tool
      ]
    end

    def run_research_graph_tool
      MCP::Tool.define(
        name: "run_research_graph",
        description: <<~TEXT.squish,
          Research Graph で調査する（メモ想起→Web 検索→URL 取得→ドラフト合成→最終回答）。
          ドラフト承認は行わず、そのまま最終回答まで進む。
          auto_approve は互換のため受け付けるが動作には影響しない。
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
              description: "互換用（無視される）。常に最終回答まで実行する"
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
        description: "run_research_graph の実行状態とドラフト・最終回答を取得する。",
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
        run = AgentGraphResponse.find_run(agent_run_id, graph_name: GRAPH_NAME)
        unless run
          return AgentGraphResponse.missing_run(agent_run_id)
        end

        Mcp::ResearchGraphTools.success_response(run)
      end
    end

    def success_response(run)
      AgentGraphResponse.success(run, summary: AgentGraph::Registry.summary_for(GRAPH_NAME))
    end

    def error_response(message)
      AgentGraphResponse.error(message)
    end
  end
end
