# frozen_string_literal: true

module Mcp
  module MemoUpdateGraphTools
    module_function

    def mcp_tools
      [
        run_memo_update_graph_tool,
        get_memo_update_graph_tool,
        resume_memo_update_graph_tool
      ]
    end

    def run_memo_update_graph_tool
      MCP::Tool.define(
        name: "run_memo_update_graph",
        description: <<~TEXT.squish,
          MemoUpdate Graph で既存の徒然メモを更新する（get_memo→草案→承認→update_memo）。
          mode は append（既定）または replace。auto_approve=true（既定）なら承認をスキップする。
        TEXT
        input_schema: {
          type: "object",
          properties: {
            instruction: { type: "string", description: "更新指示" },
            memo_ref: { type: "string", description: "更新対象メモの uid または id" },
            body: { type: "string", description: "追記または置換する Markdown 本文" },
            title: { type: "string", description: "新タイトル（省略可）" },
            mode: { type: "string", enum: %w[append replace], description: "append または replace" },
            chat_id: { type: "integer", description: "既存 Chat id。省略時は MCP 用チャットを新規作成" },
            auto_approve: { type: "boolean", description: "true（既定）なら承認を自動で通す" }
          },
          required: %w[instruction memo_ref]
        },
        annotations: {
          read_only_hint: false,
          destructive_hint: true,
          idempotent_hint: false,
          open_world_hint: false
        }
      ) do |instruction:, memo_ref:, body: nil, title: nil, mode: nil, chat_id: nil, auto_approve: true, **|
        auto = auto_approve.nil? ? true : ActiveModel::Type::Boolean.new.cast(auto_approve)
        run = AgentGraph::MemoUpdateGraphRunner.call_for_mcp(
          instruction: instruction,
          memo_ref: memo_ref,
          chat_id: chat_id,
          auto_approve: auto,
          body: body,
          title: title,
          mode: mode
        )
        Mcp::MemoUpdateGraphTools.success_response(run)
      rescue ArgumentError => e
        Mcp::MemoUpdateGraphTools.error_response(e.message)
      rescue StandardError => e
        Rails.logger.error("run_memo_update_graph failed: #{e.full_message}")
        Mcp::MemoUpdateGraphTools.error_response(e.message)
      end
    end

    def get_memo_update_graph_tool
      MCP::Tool.define(
        name: "get_memo_update_graph",
        description: "run_memo_update_graph / resume_memo_update_graph の実行状態と更新結果を取得する。",
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
        run = AgentGraphResponse.find_run(agent_run_id, graph_name: AgentGraph::MemoUpdateGraph::NAME)
        unless run
          return AgentGraphResponse.missing_run(agent_run_id)
        end

        Mcp::MemoUpdateGraphTools.success_response(run)
      end
    end

    def resume_memo_update_graph_tool
      MCP::Tool.define(
        name: "resume_memo_update_graph",
        description: "awaiting_approval の MemoUpdate Graph を承認または却下して再開する。",
        input_schema: {
          type: "object",
          properties: {
            agent_run_id: { type: "integer", description: "AgentRun の id" },
            decision: {
              type: "string",
              enum: %w[approved rejected],
              description: "approved で update_memo / rejected で終了"
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
        run = AgentGraphResponse.find_run(agent_run_id, graph_name: AgentGraph::MemoUpdateGraph::NAME)
        unless run
          return AgentGraphResponse.missing_run(agent_run_id)
        end
        unless run.awaiting_approval?
          return AgentGraphResponse.not_awaiting_approval(run)
        end

        completed = AgentGraph::MemoUpdateGraphRunner.resume(run, decision: decision)
        Mcp::MemoUpdateGraphTools.success_response(completed)
      rescue ArgumentError => e
        Mcp::MemoUpdateGraphTools.error_response(e.message)
      rescue StandardError => e
        Rails.logger.error("resume_memo_update_graph failed: #{e.full_message}")
        Mcp::MemoUpdateGraphTools.error_response(e.message)
      end
    end

    def success_response(run)
      AgentGraphResponse.success(
        run,
        summary: AgentGraph::MemoUpdateRunSummary,
        resume_tool: "resume_memo_update_graph"
      )
    end

    def error_response(message)
      AgentGraphResponse.error(message)
    end
  end
end
