# frozen_string_literal: true

module ChatTruncationAdvice
  module_function

  def message_for(chat)
    window = context_window_for(chat)
    max = ChatLlmSettings.effective_for(chat).max_tokens

    if window.positive? && (max.nil? || max > window)
      <<~TEXT.strip
        応答は途中で打ち切られました。
        このモデルのコンテキスト上限は #{window} tokens です（llama-server の -c / --ctx-size）。
        max_tokens#{max ? "=#{max}" : ""} を指定しても、プロンプト＋応答の合計はこの上限を超えられません。
        サーバのコンテキストを広げるか、会話・質問を短くしてから再度お試しください。
      TEXT
    else
      <<~TEXT.strip
        応答は途中で打ち切られました（生成上限 / truncated）。
        チャット設定で max_tokens を増やすか、質問を短くしてから再度お試しください。
      TEXT
    end
  end

  def inline_html_for(chat)
    window = context_window_for(chat)
    max = ChatLlmSettings.effective_for(chat).max_tokens

    if window.positive? && (max.nil? || max > window)
      "このモデルのコンテキスト上限は #{number_with_delimiter(window)} tokens です（llama-server の -c / --ctx-size）。" \
        "max_tokens をそれより大きくしても、プロンプト＋応答の合計はこの上限までです。サーバの ctx を広げるか、会話を短くしてください。"
    else
      "生成上限（max_tokens / n_predict）に達しています。チャット設定で max_tokens を増やすか、質問を短くしてください。"
    end
  end

  def context_window_for(chat)
    chat.model_association&.context_window.to_i
  end

  def number_with_delimiter(n)
    ActiveSupport::NumberHelper.number_to_delimited(n)
  end
end
