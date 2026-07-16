# frozen_string_literal: true

module AgentGraph
  class McpRunRequest
    def self.resolve(chat_id:, user_content:, required_name:)
      content = required_string(user_content, name: required_name)
      chat = McpChatResolver.resolve(chat_id: chat_id, user_content: content)
      [ chat, content ]
    end

    def self.required_string(value, name:)
      text = value.to_s.strip
      raise ArgumentError, "#{name} required" if text.blank?

      text
    end
  end
end
