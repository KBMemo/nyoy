# frozen_string_literal: true

module AgentGraph
  class ImageUnderstandingGraphRunner
    def self.call(chat, question: nil, attachment_index: 0, tsuzura_media_id: nil)
      new(
        chat,
        question: question,
        attachment_index: attachment_index,
        tsuzura_media_id: tsuzura_media_id
      ).call
    end

    def self.resume(agent_run, decision:)
      raise ArgumentError, "ImageUnderstanding Graph approval resume is not supported"
    end

    def self.call_for_mcp(question:, chat_id: nil, attachment_index: 0, tsuzura_media_id: nil)
      question = McpRunRequest.required_string(question, name: "question")
      chat = McpChatResolver.resolve(chat_id: chat_id, user_content: question)
      call(
        chat,
        question: question,
        attachment_index: attachment_index,
        tsuzura_media_id: tsuzura_media_id
      )
    end

    def initialize(chat, question: nil, attachment_index: 0, tsuzura_media_id: nil)
      @chat = chat
      @question = question
      @attachment_index = attachment_index.to_i
      @tsuzura_media_id = tsuzura_media_id
    end

    def call
      message = latest_user_message

      RunLauncher.for_graph(
        chat: @chat,
        graph_name: ImageUnderstandingGraph::NAME,
        state: ImageUnderstandingInitialState.build(
          chat: @chat,
          question: @question.presence || message&.content,
          message: message,
          attachment_index: @attachment_index,
          tsuzura_media_id: @tsuzura_media_id
        )
      )
    end

    private

    def latest_user_message
      @chat.messages.where(role: :user).order(:id).last
    end
  end
end
