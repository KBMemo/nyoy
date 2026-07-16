# frozen_string_literal: true

module Mcp
  module ToolCatalog
    module_function

    def tools(server_context:)
      chat_tools = ToolBridge.mcp_tools(server_context: server_context)
      extension_tools = ExtensionTools.mcp_tools
      research_tools = ResearchGraphTools.mcp_tools
      image_understanding_tools = ImageUnderstandingGraphTools.mcp_tools
      memo_write_tools = MemoWriteGraphTools.mcp_tools
      memo_update_tools = MemoUpdateGraphTools.mcp_tools
      chat_tools + extension_tools + research_tools + image_understanding_tools + memo_write_tools + memo_update_tools
    end
  end
end
