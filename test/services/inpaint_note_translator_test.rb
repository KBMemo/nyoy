# frozen_string_literal: true

require "test_helper"

class InpaintNoteTranslatorTest < ActiveSupport::TestCase
  FakeClient = Struct.new(:response, keyword_init: true) do
    def chat(messages:, temperature:, max_tokens:)
      response
    end

    def message_text(response)
      LlamaCppClient.message_text(response)
    end
  end

  test "japanese? detects hiragana" do
    assert InpaintNoteTranslator.japanese?("手を自然に")
    assert_not InpaintNoteTranslator.japanese?("natural hands")
  end

  test "translate uses llama via sd prompt translator" do
    client = FakeClient.new(
      response: {
        "choices" => [
          { "message" => { "content" => "natural hands, detailed fingers" } }
        ]
      }
    )

    translator = SdPromptTranslator.new(client: client)
    result = InpaintNoteTranslator.new(translator: translator).translate("手を自然に")

    assert_equal "natural hands, detailed fingers", result
  end

  test "translate prefers inpaint knowledge chunk as system prompt" do
    chunk = PromptKnowledgeChunk.create!(
      title: InpaintNoteTranslator::SKILL_TITLE,
      kind: "inpaint",
      body: "custom inpaint system prompt"
    )

    captured_messages = nil
    client = Class.new do
      define_method(:chat) do |messages:, temperature:, max_tokens:|
        captured_messages = messages
        { "choices" => [{ "message" => { "content" => "fixed hands" } }] }
      end

      define_method(:message_text) { |response| LlamaCppClient.message_text(response) }
    end.new

    InpaintNoteTranslator.new(translator: SdPromptTranslator.new(client: client)).translate("手")

    assert_equal "custom inpaint system prompt", captured_messages.first[:content]
  ensure
    chunk&.destroy
  end
end
