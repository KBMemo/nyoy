# frozen_string_literal: true

module Mcp
  # MCP-only MemoWrite Graph tools (not exposed to the Chat tool loop).
  module MemoWriteGraphTools
    GRAPH_NAME = AgentGraph::MemoWriteGraph::NAME

    module_function

    def mcp_tools
      [
        run_memo_write_graph_tool,
        get_memo_write_graph_tool,
        resume_memo_write_graph_tool
      ]
    end

    def run_memo_write_graph_tool
      MCP::Tool.define(
        name: "run_memo_write_graph",
        description: <<~TEXT.squish,
          MemoWrite Graph で徒然に新規メモを保存する（草案→承認→create_memo）。
          auto_approve=true（既定）なら承認をスキップする。
          body を渡すとその本文を保存する。省略時は Chat の直近 assistant 応答、
          それも無ければ instruction から保存フレーズを除いた文を使う。
          awaiting_approval のときは draft を確認して resume_memo_write_graph を呼ぶ。
        TEXT
        input_schema: {
          type: "object",
          properties: {
            instruction: {
              type: "string",
              description: "保存指示（例: これを徒然に保存して）"
            },
            body: {
              type: "string",
              description: "保存する Markdown 本文（省略可）"
            },
            title: {
              type: "string",
              description: "タイトル（省略可）"
            },
            chat_id: {
              type: "integer",
              description: "既存 Chat id。省略時は MCP 用チャットを新規作成"
            },
            auto_approve: {
              type: "boolean",
              description: "true（既定）なら承認を自動で通す。false なら承認待ち"
            }
          },
          required: [ "instruction" ]
        },
        annotations: {
          read_only_hint: false,
          destructive_hint: true,
          idempotent_hint: false,
          open_world_hint: false
        }
      ) do |instruction:, body: nil, title: nil, chat_id: nil, auto_approve: true, **|
        auto = auto_approve.nil? ? true : ActiveModel::Type::Boolean.new.cast(auto_approve)
        run = AgentGraph::MemoWriteGraphRunner.call_for_mcp(
          instruction: instruction,
          chat_id: chat_id,
          auto_approve: auto,
          body: body,
          title: title
        )
        Mcp::MemoWriteGraphTools.success_response(run)
      rescue ArgumentError => e
        Mcp::MemoWriteGraphTools.error_response(e.message)
      rescue StandardError => e
        Rails.logger.error("run_memo_write_graph failed: #{e.full_message}")
        Mcp::MemoWriteGraphTools.error_response(e.message)
      end
    end

    def get_memo_write_graph_tool
      MCP::Tool.define(
        name: "get_memo_write_graph",
        description: "run_memo_write_graph / resume_memo_write_graph の実行状態とドラフト・保存結果を取得する。",
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

        Mcp::MemoWriteGraphTools.success_response(run)
      end
    end

    def resume_memo_write_graph_tool
      MCP::Tool.define(
        name: "resume_memo_write_graph",
        description: "awaiting_approval の MemoWrite Graph を承認または却下して再開する。",
        input_schema: {
          type: "object",
          properties: {
            agent_run_id: { type: "integer", description: "AgentRun の id" },
            decision: {
              type: "string",
              enum: %w[approved rejected],
              description: "approved で create_memo / rejected で終了"
            }
          },
          required: %w[agent_run_id decision]
        },
        annotations: {
          read_only_hint: false,
          destructive_hint: true,
          idempotent_hint: false,
          open_world_hint: false
        }
      ) do |agent_run_id:, decision:, **|
        run = AgentGraphResponse.find_run(agent_run_id, graph_name: GRAPH_NAME)
        unless run
          return AgentGraphResponse.missing_run(agent_run_id)
        end
        unless run.awaiting_approval?
          return AgentGraphResponse.not_awaiting_approval(run)
        end

        completed = AgentGraph::MemoWriteGraphRunner.resume(run, decision: decision)
        Mcp::MemoWriteGraphTools.success_response(completed)
      rescue ArgumentError => e
        Mcp::MemoWriteGraphTools.error_response(e.message)
      rescue StandardError => e
        Rails.logger.error("resume_memo_write_graph failed: #{e.full_message}")
        Mcp::MemoWriteGraphTools.error_response(e.message)
      end
    end

    def success_response(run)
      AgentGraphResponse.success(
        run,
        summary: AgentGraph::Registry.summary_for(GRAPH_NAME),
        resume_tool: AgentGraph::Registry.resume_tool_for(GRAPH_NAME)
      )
    end

    def error_response(message)
      AgentGraphResponse.error(message)
    end
  end
end
