# frozen_string_literal: true

class ChatContextBudget
  Allocation = Data.define(:summary_tokens, :rag_tokens)

  def self.allocate(chat)
    window = chat.model_association&.context_window.to_i
    window = 8192 if window <= 0

    reserve = positive_int(Rails.application.config.x.nyoy.chat_response_token_reserve, 2000)
    usable = (window * warn_ratio).to_i - reserve
    usable = [usable, 1024].max

    summary_cap = positive_int(Rails.application.config.x.nyoy.chat_summary_max_tokens, 300)
    rag_cap = positive_int(Rails.application.config.x.nyoy.memo_rag_max_tokens, 1500)

    Allocation.new(
      summary_tokens: [summary_cap, (usable * 0.12).to_i].min,
      rag_tokens: [rag_cap, (usable * 0.4).to_i].min
    )
  end

  def self.trim_text(text, max_tokens:)
    return nil if text.blank?

    max_chars = positive_int(max_tokens, 0) * ChatTokenEstimator::CHARS_PER_TOKEN.to_i
    return text if max_chars <= 0

    trimmed = text.to_s
    return trimmed if trimmed.bytesize <= max_chars

    suffix = "…"
    keep = max_chars - suffix.bytesize
    keep = 1 if keep < 1
    "#{trimmed.byteslice(0, keep)}#{suffix}"
  end

  def self.warn_ratio
    ratio = Rails.application.config.x.nyoy.chat_context_token_warn_ratio.to_f
    ratio.positive? ? [ratio, 0.95].min : 0.85
  end

  def self.positive_int(value, fallback)
    parsed = value.to_i
    parsed.positive? ? parsed : fallback
  end
  private_class_method :positive_int, :warn_ratio
end
