# frozen_string_literal: true

require "test_helper"

class LlamaWarmupServiceTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
    @chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
    @original_enabled = Rails.application.config.x.nyoy.llama_warmup_enabled
    @original_skip = Rails.application.config.x.nyoy.llama_warmup_skip_recent_seconds
    @original_llama_new = LlamaCppClient.method(:new)
    Rails.application.config.x.nyoy.llama_warmup_enabled = true
    Rails.application.config.x.nyoy.llama_warmup_skip_recent_seconds = 480
  end

  teardown do
    Rails.application.config.x.nyoy.llama_warmup_enabled = @original_enabled
    Rails.application.config.x.nyoy.llama_warmup_skip_recent_seconds = @original_skip
    LlamaCppClient.define_singleton_method(:new, @original_llama_new)
  end

  test "warms each chat backend with a one-token completion when idle" do
    calls = []
    stub_llama_client { |kwargs, chat_args| calls << { init: kwargs, chat: chat_args } }

    result = LlamaWarmupService.call

    assert_equal [true], result.uniq
    assert calls.any?, "expected at least one backend to be warmed"
    calls.each do |call|
      assert_equal 1, call[:chat][:max_tokens]
      assert_equal 0, call[:chat][:temperature]
    end
  end

  test "skips warmup when disabled" do
    Rails.application.config.x.nyoy.llama_warmup_enabled = false
    stub_llama_client { |_kwargs, _chat_args| flunk("should not warm when disabled") }

    assert_equal [], LlamaWarmupService.call
  end

  test "skips warmup when a chat is recently active" do
    @chat.messages.create!(role: :user, content: "hello")
    stub_llama_client { |_kwargs, _chat_args| flunk("should not warm during active chat") }

    assert_equal [], LlamaWarmupService.call(now: Time.current)
  end

  test "warms when the last activity is older than the skip window" do
    @chat.messages.create!(role: :user, content: "hello")
    calls = []
    stub_llama_client { |kwargs, chat_args| calls << { init: kwargs, chat: chat_args } }

    LlamaWarmupService.call(now: Time.current + 10.minutes)

    assert calls.any?
  end

  private

  def stub_llama_client
    LlamaCppClient.define_singleton_method(:new) do |**kwargs|
      client = Object.new
      client.define_singleton_method(:chat) do |**chat_args|
        yield(kwargs, chat_args)
        {}
      end
      client
    end
  end
end
