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

  def chat_message_first_chunk_elapsed(message)
    return unless message.first_chunk_elapsed_ms.present?

    message.first_chunk_elapsed_ms / 1000.0
  end

  def chat_message_context_build_elapsed(message)
    return unless message.context_build_elapsed_ms.present?

    message.context_build_elapsed_ms / 1000.0
  end

  def chat_message_llama_cache_label(message)
    return unless message.llama_cache_prompt == true || message.llama_cache_slot_id.present?

    parts = []
    parts << "prompt" if message.llama_cache_prompt == true
    if message.llama_cache_slot_id.present?
      slot = message.llama_cache_slot_id
      slot = "#{slot}/#{message.llama_cache_slot_count}" if message.llama_cache_slot_count.present?
      parts << "slot #{slot}"
    end
    parts.join(" / ")
  end

  def chat_message_stats(message)
    stats = []
    stats << { label: "モデル", value: chat_message_model_name(message) }

    response_elapsed = chat_message_response_elapsed(message)
    stats << { label: "経過", value: nyoy_format_duration(response_elapsed) } if response_elapsed

    first_chunk_elapsed = chat_message_first_chunk_elapsed(message)
    stats << { label: "初回応答", value: nyoy_format_duration(first_chunk_elapsed) } if first_chunk_elapsed

    context_build_elapsed = chat_message_context_build_elapsed(message)
    stats << { label: "前処理", value: nyoy_format_duration(context_build_elapsed) } if context_build_elapsed

    thinking_elapsed = chat_message_thinking_elapsed(message)
    stats << { label: "思考", value: nyoy_format_duration(thinking_elapsed) } if thinking_elapsed

    llama_cache = chat_message_llama_cache_label(message)
    stats << { label: "KV cache", value: llama_cache } if llama_cache.present?

    stats
  end

  def default_model_display_name
    model = ChatModelCatalog.default_model
    label = model&.name.presence || RubyLLM.config.default_model
    "デフォルト: #{label}"
  end

  def chat_context_turn_limit
    Rails.application.config.x.nyoy.chat_context_turns.to_i
  end

  def chat_context_stats(chat)
    ChatContextStats.for(chat)
  end

  def memo_rag_status
    MemoRagStatus.current
  end

  def tool_result_partial(message)
    name = message.respond_to?(:parent_tool_call) ? message.parent_tool_call&.name.to_s : ""
    partial_for(prefix: "messages/tool_results", name: name)
  end

  def tool_call_partial(tool_call)
    partial_for(prefix: "messages/tool_calls", name: tool_call.name.to_s)
  end

  def tool_call_body(tool_call)
    "#{tool_call.name}(#{tool_call.arguments.map { |k, v| "#{k}: #{v.inspect}" }.join(", ")})"
  end

  def tool_message_preview(text, length: 80)
    text.to_s.gsub(/\s+/, " ").strip.truncate(length)
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
