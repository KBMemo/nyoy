# frozen_string_literal: true

module AgentGraph
  module McpChatResolver
    module_function

    def resolve(chat_id:, user_content:)
      if chat_id.present?
        chat = Chat.find_by(id: chat_id)
        raise ArgumentError, "chat not found: #{chat_id}" unless chat

        return chat
      end

      model = ChatModelCatalog.default_model || Model.order(:id).first
      raise ArgumentError, "no chat model available" unless model

      chat = Chat.create!(model: model)
      Message.suppressing_turbo_broadcasts do
        chat.messages.create!(role: :user, content: user_content.to_s)
      end
      chat
    end
  end
end
