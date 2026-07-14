# frozen_string_literal: true

require "json"

module ChatTools
  # Plain-text tool results that models reliably interpret (ruby_llm turns Hash
  # values into Ruby inspect strings, which some models ignore).
  module ToolResponse
    LIMIT_PREFIX = "[TOOL_LIMIT_REACHED]"
    ERROR_PREFIX = "[TOOL_ERROR]"

    module_function

    def preview(payload)
      JSON.generate(utf8_deep(payload.compact))
    end

    # Tool payloads often include HTTP-sourced strings tagged as ASCII-8BIT.
    # JSON.generate raises on incomplete UTF-8 labeled as BINARY.
    def utf8_deep(value)
      case value
      when Hash
        value.transform_values { |v| utf8_deep(v) }
      when Array
        value.map { |v| utf8_deep(v) }
      when String
        value.dup.force_encoding(Encoding::UTF_8).scrub("")
      else
        value
      end
    end

    def limit_reached(tool:, message:, code: "LIMIT_EXCEEDED", url: nil, exhausted: true)
      failure(
        prefix: LIMIT_PREFIX,
        tool: tool,
        code: code,
        message: message,
        retryable: false,
        exhausted: exhausted,
        url: url,
        next_action: "このターンでは #{tool} を再実行してはいけません。同じ URL も別 URL も取得せず、既にある情報だけで回答してください。"
      )
    end

    def error(tool:, message:, code: "TOOL_ERROR", retryable: false, url: nil, next_action: nil)
      failure(
        prefix: ERROR_PREFIX,
        tool: tool,
        code: code,
        message: message,
        retryable: retryable,
        url: url,
        next_action: next_action || "このエラーはツールの実行結果です。同じ操作を繰り返さず、別の方法で回答するか、ユーザーに状況を説明してください。"
      )
    end

    def failure(prefix:, tool:, code:, message:, retryable:, next_action:, exhausted: false, url: nil)
      lines = [
        "#{prefix}: #{tool}",
        "CODE: #{code}",
        "RETRYABLE: #{retryable}",
        exhausted ? "EXHAUSTED: true" : nil,
        url.present? ? "URL: #{url}" : nil,
        "",
        message,
        "",
        next_action
      ].compact

      lines.join("\n")
    end
  end
end
