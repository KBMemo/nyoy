# frozen_string_literal: true

class ChatErrorBroadcaster
  ERROR_PREFIX = "[[nyoy-error]]"
  UNREACHABLE_PATTERN = /
    Connection\ refused
    | Failed\ to\ open\ TCP\ connection
    | Connection\ reset
    | ECONNREFUSED
    | Couldn't\ connect
    | getaddrinfo
    | Name\ or\ service\ not\ known
    | Network\ is\ unreachable
    | Faraday::ConnectionFailed
    | Net::OpenTimeout
    | Net::ReadTimeout
    | execution\ expired
  /xi

  def self.fail!(chat, error)
    new(chat, error).call
  end

  def initialize(chat, error)
    @chat = chat
    @error = error
  end

  def call
    @chat.reload
    remove_blank_assistant!
    message = create_error_message!
    reset_form!
    message
  end

  private

  def remove_blank_assistant!
    assistant = @chat.messages.where(role: :assistant).order(:id).last
    return if assistant.nil?
    return unless assistant.content.blank? && assistant.thinking_text.blank?

    assistant.destroy!
  end

  def create_error_message!
    @chat.messages.create!(role: :assistant, content: "#{ERROR_PREFIX}#{friendly_message}")
  end

  def reset_form!
    ChatUiBroadcaster.form_updated(@chat)
  end

  def friendly_message
    if context_length_error?
      <<~TEXT.strip
        会話が長すぎます（コンテキスト上限を超えました）。新しいチャットを始めるか、過去のメッセージを減らしてください。

        #{@error.message}
      TEXT
    elsif llm_unreachable_error?
      <<~TEXT.strip
        モデルサーバーに接続できません。LLM サーバーが起動しているか確認してください。

        #{@error.message}
      TEXT
    elsif llm_error?
      # Provider/HTTP errors carry useful, user-facing detail (rate limits,
      # bad request reasons, etc.), so surface the raw message.
      <<~TEXT.strip
        応答の取得に失敗しました。

        #{@error.message}
      TEXT
    elsif research_graph_error?
      <<~TEXT.strip
        調査フローが失敗しました。

        #{@error.message}
      TEXT
    elsif output_truncated_error?
      ChatTruncationBroadcaster::MESSAGE
    else
      # Unexpected internal errors (bugs) should not leak their raw message to
      # the UI; the full error is already written to the log by ChatResponseJob.
      "応答の取得に失敗しました。しばらくしてからもう一度お試しください。"
    end
  end

  def llm_error?
    @error.is_a?(RubyLLM::Error)
  end

  def research_graph_error?
    defined?(AgentGraph::Error) && @error.is_a?(AgentGraph::Error)
  end

  def llm_unreachable_error?
    return true if defined?(Faraday::ConnectionFailed) && @error.is_a?(Faraday::ConnectionFailed)
    return true if @error.is_a?(Errno::ECONNREFUSED)
    return true if @error.is_a?(SocketError)
    return true if @error.is_a?(Timeout::Error)

    @error.message.to_s.match?(UNREACHABLE_PATTERN)
  end

  def context_length_error?
    return true if @error.is_a?(RubyLLM::ContextLengthExceededError)

    @error.message.to_s.match?(/context size|context length|context window|too many tokens|token count exceeds/i)
  end

  def output_truncated_error?
    @error.message.to_s.match?(/finish_reason.*length|max_tokens|n_predict|truncated\s*=\s*1/i)
  end
end
