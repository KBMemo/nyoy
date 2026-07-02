# frozen_string_literal: true

require "test_helper"

class ChatHistorySummarizerTest < ActiveSupport::TestCase
  test "summarizes old turns with rule-based fallback" do
    messages = [
      Message.new(role: :user, content: "最初の質問です"),
      Message.new(role: :assistant, content: "最初の回答です")
    ]

    summary = ChatHistorySummarizer.new(llm_enabled: false).summarize(messages)

    assert_includes summary, "最初の質問"
    assert_includes summary, "最初の回答"
  end
end
