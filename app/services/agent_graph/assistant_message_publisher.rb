# frozen_string_literal: true

module AgentGraph
  class AssistantMessagePublisher
    def self.call(chat, content:, truncated: false, thinking_text: nil, clear_approval: true)
      new(chat).call(
        content: content,
        truncated: truncated,
        thinking_text: thinking_text,
        clear_approval: clear_approval
      )
    end

    def initialize(chat)
      @chat = chat
    end

    def call(content:, truncated: false, thinking_text: nil, clear_approval: true)
      message = create_message!(
        content: content,
        truncated: truncated,
        thinking_text: thinking_text
      )
      ChatUiBroadcaster.message_upsert(message)
      ChatTruncationBroadcaster.call(@chat) if truncated
      ApprovalBroadcaster.clear!(@chat) if clear_approval
      message
    end

    private

    def create_message!(content:, truncated:, thinking_text:)
      Message.suppressing_turbo_broadcasts do
        @chat.messages.create!(
          role: :assistant,
          content: content,
          truncated: truncated,
          thinking_text: thinking_text
        )
      end
    end
  end
end
