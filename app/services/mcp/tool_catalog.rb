# frozen_string_literal: true

module Mcp
  module ToolCatalog
    module_function

    def tools(server_context:)
      chat_tools = ToolBridge.mcp_tools(server_context: server_context)
      extension_tools = ExtensionTools.mcp_tools
      chat_tools + extension_tools
    end
  end
end
