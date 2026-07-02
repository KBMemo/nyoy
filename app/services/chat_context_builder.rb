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
    old_messages = old_turns.flatten
    recent_messages = turns.last(max_turns).flatten
    summary = summarize_old_turns(old_messages)

    Result.new(
      messages: system_messages + recent_messages,
      summary: summary,
      summarized_turns: old_turns.size
    )
  end

  private

  def summarize_old_turns(messages)
    return nil unless Rails.application.config.x.nyoy.chat_summary_enabled
    return nil if messages.empty?

    boundary_id = messages.filter_map(&:id).max
    if boundary_id.present? &&
       @chat.context_summary.present? &&
       @chat.context_summary_until_message_id == boundary_id
      return @chat.context_summary
    end

    summary = ChatHistorySummarizer.new.summarize(messages)
    return nil if summary.blank? || boundary_id.blank?

    allocation = ChatContextBudget.allocate(@chat)
    summary = ChatContextBudget.trim_text(summary, max_tokens: allocation.summary_tokens)
    @chat.update_columns(context_summary: summary, context_summary_until_message_id: boundary_id)
    summary
  end
end
