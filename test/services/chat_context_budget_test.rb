# frozen_string_literal: true

require "test_helper"

class ChatContextBudgetTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
    @chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
  end

  test "allocates summary and rag token budgets from context window" do
    allocation = ChatContextBudget.allocate(@chat)

    assert allocation.summary_tokens.positive?
    assert allocation.rag_tokens.positive?
    assert allocation.rag_tokens > allocation.summary_tokens
  end

  test "trims text to token budget" do
    text = "a" * 4000
    trimmed = ChatContextBudget.trim_text(text, max_tokens: 100)

    assert_operator trimmed.bytesize, :<=, 400
  end
end
