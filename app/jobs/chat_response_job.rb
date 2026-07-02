class ChatResponseJob < ApplicationJob
  def perform(chat_id, content)
    chat = Chat.find(chat_id)
    timer = ChatResponseTimer.new

    chat.ask(content) do |chunk|
      timer.observe_chunk!(chunk)

      if chunk.content.present?
        message = chat.messages.last
        message.broadcast_append_chunk(chunk.content)
      end
    end

    persist_assistant_timing(chat, timer)
  rescue RubyLLM::Error, StandardError => e
    ChatErrorBroadcaster.fail!(chat, e)
  end

  private

  def persist_assistant_timing(chat, timer)
    assistant_message = chat.messages.where(role: :assistant).order(:id).last
    return unless assistant_message

    assistant_message.update!(timer.message_timing_attributes)
  end
end
