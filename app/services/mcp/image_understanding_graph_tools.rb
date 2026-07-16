# frozen_string_literal: true

module Mcp
  module ImageUnderstandingGraphTools
    GRAPH_NAME = AgentGraph::ImageUnderstandingGraph::NAME

    module_function

    def mcp_tools
      [
        run_image_understanding_graph_tool,
        get_image_understanding_graph_tool,
        retry_image_understanding_graph_tool
      ]
    end

    def run_image_understanding_graph_tool
      MCP::Tool.define(
        name: "run_image_understanding_graph",
        description: <<~TEXT.squish,
          ImageUnderstanding Graph で画像の視覚的内容を解析して回答する。
          MCP では tsuzura_media_id 指定を推奨する。chat_id を指定する場合は、その Chat の直近 user message 添付を使う。
        TEXT
        input_schema: {
          type: "object",
          properties: {
            question: {
              type: "string",
              description: "画像に対する質問や解析指示"
            },
            tsuzura_media_id: {
              type: "string",
              description: "葛籠 media id。MCP ではこの指定を推奨"
            },
            chat_id: {
              type: "integer",
              description: "既存 Chat id。指定時は直近 user message の添付画像を利用可能"
            },
            attachment_index: {
              type: "integer",
              description: "Chat 添付画像の番号（0 始まり）。省略時は 0"
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
      ) do |question:, tsuzura_media_id: nil, chat_id: nil, attachment_index: 0, **|
        run = AgentGraph::ImageUnderstandingGraphRunner.call_for_mcp(
          question: question,
          chat_id: chat_id,
          attachment_index: attachment_index || 0,
          tsuzura_media_id: tsuzura_media_id
        )
        Mcp::ImageUnderstandingGraphTools.success_response(run)
      rescue ArgumentError => e
        Mcp::ImageUnderstandingGraphTools.error_response(e.message)
      rescue StandardError => e
        Rails.logger.error("run_image_understanding_graph failed: #{e.full_message}")
        Mcp::ImageUnderstandingGraphTools.error_response(e.message)
      end
    end

    def get_image_understanding_graph_tool
      MCP::Tool.define(
        name: "get_image_understanding_graph",
        description: "run_image_understanding_graph の実行状態と画像解析結果を取得する。",
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
        run, error = AgentGraphResponse.find_run_or_error(agent_run_id, graph_name: GRAPH_NAME)
        return error if error

        Mcp::ImageUnderstandingGraphTools.success_response(run)
      end
    end

    def retry_image_understanding_graph_tool
      MCP::Tool.define(
        name: "retry_image_understanding_graph",
        description: "failed の ImageUnderstanding Graph を、最後の成功 checkpoint から複製 run として retry する。",
        input_schema: {
          type: "object",
          properties: {
            agent_run_id: { type: "integer", description: "retry 元の failed AgentRun id" }
          },
          required: [ "agent_run_id" ]
        },
        annotations: {
          read_only_hint: false,
          destructive_hint: false,
          idempotent_hint: false,
          open_world_hint: true
        }
      ) do |agent_run_id:, **|
        run, error = AgentGraphResponse.find_run_or_error(agent_run_id, graph_name: GRAPH_NAME)
        return error if error

        retry_run = AgentGraph::RunRetryLauncher.call(run)
        Mcp::ImageUnderstandingGraphTools.success_response(retry_run)
      rescue ArgumentError => e
        Mcp::ImageUnderstandingGraphTools.error_response(e.message)
      rescue StandardError => e
        Rails.logger.error("retry_image_understanding_graph failed: #{e.full_message}")
        Mcp::ImageUnderstandingGraphTools.error_response(e.message)
      end
    end

    def success_response(run)
      AgentGraphResponse.success_for_graph(run, graph_name: GRAPH_NAME)
    end

    def error_response(message)
      AgentGraphResponse.error(message)
    end
  end
end
