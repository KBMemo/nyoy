# frozen_string_literal: true

class ChatChannel < ApplicationCable::Channel
  def subscribed
    chat = Chat.find_by(id: params[:chat_id])
    return reject unless chat

    stream_for chat
  end
end
