# frozen_string_literal: true

class ChatHistorySummarizer
  SYSTEM_PROMPT = <<~TEXT.squish
    あなたは会話要約器です。与えられた過去の会話から、後続の回答に必要な事実・決定・未解決点だけを
    日本語の箇条書き 5 件以内で短くまとめてください。挨拶や冗長な説明は省略してください。
  TEXT

  def initialize(
    llm_enabled: Rails.application.config.x.nyoy.chat_summary_llm,
    max_chars: Rails.application.config.x.nyoy.chat_summary_max_chars,
    client: LlamaCppClient.new
  )
    @llm_enabled = llm_enabled
    @max_chars = positive_int(max_chars, 1200)
    @client = client
  end

  def summarize(messages)
    transcript = format_transcript(messages)
    return nil if transcript.blank?
    return truncate(transcript) if transcript.length <= 240

    summary = @llm_enabled ? llm_summary(transcript) : nil
    summary = rule_based_summary(messages) if summary.blank?
    truncate(summary)
  end

  private

  def llm_summary(transcript)
    response = @client.chat(
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: transcript }
      ],
      temperature: 0.2,
      max_tokens: 400
    )
    LlamaCppClient.message_text(response).presence
  rescue LlamaCppClient::Error
    nil
  end

  def rule_based_summary(messages)
    lines = []
    ChatContextLimiter.turns(messages).each do |turn|
      user = turn.find { |message| message.role.to_s == "user" }
      assistant = turn.reverse.find { |message| message.role.to_s == "assistant" }
      next unless user

      line = "- ユーザー: #{excerpt(user.content)}"
      line << " / 回答: #{excerpt(assistant.content)}" if assistant&.content.present?
      lines << line
    end
    lines.join("\n")
  end

  def format_transcript(messages)
    ChatContextLimiter.turns(messages).flat_map do |turn|
      turn.filter_map do |message|
        next if message.role.to_s == "tool"

        label = message.role.to_s.capitalize
        content = message.content.to_s.strip
        next if content.blank?

        "#{label}: #{content}"
      end
    end.join("\n\n")
  end

  def excerpt(text)
    text.to_s.squish.then { |value| value.length > 120 ? "#{value[0, 117]}..." : value }
  end

  def truncate(text)
    text.to_s.byteslice(0, @max_chars)
  end

  def positive_int(value, fallback)
    parsed = value.to_i
    parsed.positive? ? parsed : fallback
  end
end
