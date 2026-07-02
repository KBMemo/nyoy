module MessagesHelper
  def render_chat_markdown(text)
    ChatMarkdownRenderer.render(text)
  end

  def chat_message_model_name(message)
    message.model&.name.presence || message.chat&.model&.name.presence || default_model_display_name
  end

  def chat_message_response_elapsed(message)
    if message.response_elapsed_ms.present?
      message.response_elapsed_ms / 1000.0
    elsif message.created_at.present? && message.updated_at.present?
      elapsed = message.updated_at - message.created_at
      elapsed.positive? ? elapsed : nil
    end
  end

  def chat_message_thinking_elapsed(message)
    return unless message.thinking_elapsed_ms.present?

    message.thinking_elapsed_ms / 1000.0
  end

  def chat_message_stats(message)
    stats = []
    stats << { label: "モデル", value: chat_message_model_name(message) }

    response_elapsed = chat_message_response_elapsed(message)
    stats << { label: "経過", value: nyoy_format_duration(response_elapsed) } if response_elapsed

    thinking_elapsed = chat_message_thinking_elapsed(message)
    stats << { label: "思考", value: nyoy_format_duration(thinking_elapsed) } if thinking_elapsed

    stats
  end

  def default_model_display_name
    model_id = RubyLLM.config.default_model
    label = Model.find_by(model_id: model_id, provider: "openai")&.name || model_id
    "デフォルト: #{label}"
  end

  def chat_context_turn_limit
    Rails.application.config.x.nyoy.chat_context_turns.to_i
  end

  def chat_context_stats(chat)
    ChatContextStats.for(chat)
  end

  def tool_result_partial(message)
    name = message.respond_to?(:parent_tool_call) ? message.parent_tool_call&.name.to_s : ""
    partial_for(prefix: "messages/tool_results", name: name)
  end

  def tool_call_partial(tool_call)
    partial_for(prefix: "messages/tool_calls", name: tool_call.name.to_s)
  end

  private

  def partial_for(prefix:, name:)
    normalized = name.to_s.underscore.tr("-", "_")
    if normalized.present? && lookup_context.exists?(normalized, [ prefix ], true)
      "#{prefix}/#{normalized}"
    else
      "#{prefix}/default"
    end
  end
end
