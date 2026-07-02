# frozen_string_literal: true

class ChatContextBuilder
  Result = Data.define(:messages, :summary, :summarized_turns)

  def self.build(chat)
    new(chat).build
  end

  def initialize(chat)
    @chat = chat
  end

  def build
    all_messages = @chat.messages_association.to_a
    system_messages, conversation = all_messages.partition { |message| message.role.to_s == "system" }
    turns = ChatContextLimiter.turns(conversation)
    max_turns = Rails.application.config.x.nyoy.chat_context_turns.to_i

    return Result.new(messages: all_messages, summary: nil, summarized_turns: 0) if max_turns <= 0
    return Result.new(messages: all_messages, summary: nil, summarized_turns: 0) if turns.size <= max_turns

    old_turns = turns[0...(turns.size - max_turns)]
    recent_messages = turns.last(max_turns).flatten
    summary = summarize_old_turns(old_turns.flatten)

    Result.new(
      messages: system_messages + recent_messages,
      summary: summary,
      summarized_turns: old_turns.size
    )
  end

  private

  def summarize_old_turns(messages)
    return nil unless Rails.application.config.x.nyoy.chat_summary_enabled

    ChatHistorySummarizer.new.summarize(messages)
  end
end
