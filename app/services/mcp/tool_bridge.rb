# frozen_string_literal: true

require "json"

module Mcp
  class ToolBridge
    CHAT_SCOPED_CLASSES = [
      ChatTools::AnalyzeImage,
      ChatTools::CreateMemo,
      ChatTools::UpdateMemo,
      ChatTools::RecallMemos
    ].freeze

    WEB_BUDGET_CLASSES = [
      ChatTools::WebSearch,
      ChatTools::FetchUrl
    ].freeze

    READ_ONLY_TOOLS = %w[
      web_search fetch_url search_fetched_page
      search_memos get_memo recall_memos
      list_albums get_media analyze_image
    ].freeze

    DESTRUCTIVE_TOOLS = %w[create_memo update_memo].freeze

    class << self
      def instances(web_budget:)
        ChatTools::Registry.tool_classes.map do |tool_class|
          if CHAT_SCOPED_CLASSES.include?(tool_class)
            tool_class.new(chat: nil)
          elsif WEB_BUDGET_CLASSES.include?(tool_class)
            tool_class.new(budget: web_budget)
          else
            tool_class.new
          end
        end
      end

      def mcp_tools(server_context:)
        instances(web_budget: server_context.fetch(:web_budget)).map do |instance|
          build_mcp_tool(instance)
        end
      end

      def build_mcp_tool(instance)
        tool_name = instance.name

        MCP::Tool.define(
          name: tool_name,
          description: instance.description,
          input_schema: input_schema_for(instance),
          annotations: annotations_for(tool_name)
        ) do |**kwargs|
          server_context = kwargs.delete(:server_context)
          chat_tool = server_context.fetch(:tool_instances).fetch(tool_name)
          result = chat_tool.execute(**kwargs)
          text = Mcp::ToolBridge.format_result(result)

          MCP::Tool::Response.new(
            [{ type: "text", text: text }],
            error: Mcp::ToolBridge.error_result?(result)
          )
        end
      end

      def input_schema_for(instance)
        schema = instance.params_schema
        if schema.blank?
          return { type: "object", properties: {} }
        end

        {
          type: "object",
          properties: schema["properties"] || {},
          required: schema["required"] || []
        }
      end

      def annotations_for(tool_name)
        {
          read_only_hint: READ_ONLY_TOOLS.include?(tool_name),
          destructive_hint: DESTRUCTIVE_TOOLS.include?(tool_name),
          idempotent_hint: false,
          open_world_hint: true
        }
      end

      def format_result(result)
        case result
        when String
          result
        when Hash
          JSON.generate(result)
        else
          result.to_s
        end
      end

      def error_result?(result)
        case result
        when String
          result.include?(ChatTools::ToolResponse::LIMIT_PREFIX) ||
            result.include?(ChatTools::ToolResponse::ERROR_PREFIX)
        when Hash
          result.key?(:error) || result.key?("error")
        else
          false
        end
      end
    end
  end
end
