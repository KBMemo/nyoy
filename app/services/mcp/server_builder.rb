# frozen_string_literal: true

module Mcp
  class ServerBuilder
    SERVER_NAME = "nyoy"
    SERVER_VERSION = "0.1.0"
    INSTRUCTIONS = <<~TEXT.squish
      Nyoy（如意）の Chat ツールを MCP 経由で利用できます。
      徒然メモ検索、Web 検索、URL 取得、画像解析、葛籠メディア参照など。
      create_memo / update_memo はユーザーが明示的に保存を求めたときだけ使ってください。
      analyze_image は tsuzura_media_id を指定するか、Chat 添付がない場合は画像解析に使えません。
      generate_image は非同期です。get_image_generation で進捗を確認してください。
      調査フローは run_research_graph（既定 auto_approve=true）。
      plan.sensitive のときだけ承認待ちになり、その場合は resume_research_graph で続行。
    TEXT

    class << self
      def build
        web_budget = ChatTools::WebToolBudget.from_settings
        tool_instances = ToolBridge.instances(web_budget: web_budget).index_by(&:name)
        server_context = {
          web_budget: web_budget,
          tool_instances: tool_instances
        }

        MCP::Server.new(
          name: SERVER_NAME,
          title: "Nyoy MCP",
          version: SERVER_VERSION,
          instructions: INSTRUCTIONS,
          tools: ToolCatalog.tools(server_context: server_context),
          server_context: server_context
        )
      end
    end
  end
end
