# frozen_string_literal: true

class ChatResponseControl
  class Cancelled < StandardError; end

  STATES = {
    idle: "idle",
    running: "running",
    cancelled: "cancelled"
  }.freeze

  class << self
    def mark_running!(chat)
      chat.update!(response_state: STATES[:running])
    end

    def cancel!(chat)
      chat.update!(response_state: STATES[:cancelled])
    end

    def finish!(chat)
      chat.update!(response_state: STATES[:idle])
    end

    def install_checks!(llm_chat, chat_id)
      callback = ->(*) { check!(chat_id) }
      llm_chat.before_tool_call(&callback)
      llm_chat.before_message(&callback)
    end

    def check!(chat_id)
      state = Chat.where(id: chat_id).pick(:response_state)
      raise Cancelled if state == STATES[:cancelled]

      state
    end
  end
end
