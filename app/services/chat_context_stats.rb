# frozen_string_literal: true

class ChatContextStats
  Stats = Data.define(:estimated_tokens, :context_window, :ratio, :warning, :summarized_turns)

  def self.for(chat)
    new(chat).build
  end

  def initialize(chat)
    @chat = chat
  end

  def build
    context = ChatContextBuilder.build(@chat)
    estimated = ChatTokenEstimator.estimate_messages(context.messages)
    estimated += ChatTokenEstimator.estimate_text(context.summary) if context.summary.present?

    window = @chat.model_association&.context_window.to_i
    window = 8192 if window <= 0
    ratio = estimated.to_f / window
    warn_ratio = Rails.application.config.x.nyoy.chat_context_token_warn_ratio.to_f
    warn_ratio = 0.75 if warn_ratio <= 0.0

    Stats.new(
      estimated_tokens: estimated,
      context_window: window,
      ratio: ratio,
      warning: ratio >= warn_ratio,
      summarized_turns: context.summarized_turns
    )
  end
end
