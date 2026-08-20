# frozen_string_literal: true

require "json"
require "securerandom"

module AgentGraph
  # Persists Graph tool invocations as Chat Tool Call / Tool Result messages
  # so the UI matches the normal Chat tool loop.
  class ToolTraceRecorder
    CONTENT_LIMIT = 20_000

    def self.record!(chat, name:, arguments:, result:)
      new(chat).record!(name: name, arguments: arguments, result: result)
    end

    def initialize(chat)
      @chat = chat
    end

    def record!(name:, arguments:, result:)
      call_message = nil
      result_message = nil

      Message.suppressing_turbo_broadcasts do
        ActiveRecord::Base.transaction do
          call_message = @chat.messages.create!(role: :assistant, content: "")
          tool_call = call_message.tool_calls_association.create!(
            tool_call_id: "graph_#{SecureRandom.uuid}",
            name: name.to_s,
            arguments: deep_stringify(arguments)
          )
          result_message = @chat.messages.create!(
            role: :tool,
            content: serialize_result(result),
            tool_call_id: tool_call.id
          )
        end
      end

      ChatUiBroadcaster.message_upsert(call_message.reload) if call_message
      ChatUiBroadcaster.message_upsert(result_message.reload) if result_message

      { call_message: call_message, result_message: result_message }
    end

    private

    def serialize_result(result)
      text =
        case result
        when String
          result
        when Hash
          ChatTools::ToolResponse.preview(deep_stringify(result))
        when Array
          ChatTools::ToolResponse.preview(deep_stringify(result))
        when nil
          "(no output)"
        else
          result.to_s
        end

      text.to_s.truncate(CONTENT_LIMIT)
    end

    def deep_stringify(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, nested), out|
          out[key.to_s] = deep_stringify(nested)
        end
      when Array
        value.map { |item| deep_stringify(item) }
      when String
        ChatTools::ToolResponse.safe_string(value)
      else
        value
      end
    end
  end
end
