# frozen_string_literal: true

require "json"

module AgentGraph
  module Nodes
    class FetchUrls
      def call(state:, run:, chat:)
        urls = AgentGraph::ResearchRouting.fetch_targets(state)
        if urls.empty?
          return AgentGraph::NodeResult.next
        end

        budget = ChatTools::WebToolBudget.from_graph_budget(state["budget"])
        tool = ChatTools::FetchUrl.new(budget: budget)
        pages = Array(state["fetched_pages"]).dup
        errors = Array(state["errors"]).dup
        remaining = budget.max_fetches - budget.fetches

        urls.first([ remaining, urls.size ].min).each do |url|
          raw = tool.execute(url: url)
          AgentGraph::ToolTraceRecorder.record!(
            chat,
            name: "fetch_url",
            arguments: { "url" => url },
            result: raw
          )
          parsed = parse_tool_payload(raw)
          if parsed.is_a?(Hash) && parsed["ok"]
            pages << parsed.slice(
              "page_id", "url", "status", "title", "site_name", "excerpt",
              "content_preview", "truncated", "extractor"
            ).compact
          else
            errors << {
              "node" => "fetch_urls",
              "code" => parsed.is_a?(Hash) ? parsed["code"] : "FETCH_FAILED",
              "message" => extract_error_message(raw, parsed),
              "url" => url
            }
          end
        end

        AgentGraph::NodeResult.next(updates: {
          "fetched_pages" => pages,
          "budget" => budget.to_graph_budget,
          "errors" => errors
        })
      end

      private

      def parse_tool_payload(raw)
        return raw if raw.is_a?(Hash)
        return {} if raw.blank?

        text = raw.to_s
        return { "ok" => false, "message" => text } if text.start_with?("[TOOL_")

        JSON.parse(text)
      rescue JSON::ParserError
        { "ok" => false, "message" => text.to_s.truncate(300) }
      end

      def extract_error_message(raw, parsed)
        return parsed["message"].to_s if parsed.is_a?(Hash) && parsed["message"].present?

        raw.to_s.lines.map(&:strip).reject(&:blank?).find { |line| !line.start_with?("[TOOL_", "CODE:", "RETRYABLE:", "URL:") } ||
          raw.to_s.truncate(300)
      end
    end
  end
end
