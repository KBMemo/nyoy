# frozen_string_literal: true

require "test_helper"

class AgentGraphImageUnderstandingGraphRunnerTest < ActiveSupport::TestCase
  setup do
    model = Model.find_or_create_by!(provider: "test", model_id: "image-understanding-test") do |record|
      record.name = "Image Understanding Test"
    end
    @chat = Chat.create!(model: model)
  end

  test "runs image understanding graph for chat attachment" do
    message = add_user_message(ChatImageAttachments::PLACEHOLDER)
    message.attachments.attach(io: StringIO.new("png"), filename: "pixel.png", content_type: "image/png")
    stub_vision_service("赤い四角が写っています。")

    run = AgentGraph::ImageUnderstandingGraphRunner.call(@chat)

    assert_predicate run, :completed?
    assert_equal AgentGraph::ImageUnderstandingGraph::NAME, run.graph_name
    assert_equal "画像を説明してください", run.state["question"]
    assert_equal "赤い四角が写っています。", run.state["analysis"]
    assert_equal "赤い四角が写っています。", run.state["final_answer"]
    assert_equal %w[plan_image_understanding resolve_image_source analyze_image finalize_image_answer], run.agent_node_runs.order(:id).pluck(:node_name)

    assistant = @chat.messages.where(role: :assistant).last
    assert_equal "赤い四角が写っています。", assistant.content
    assert_equal assistant.id, run.state["assistant_message_id"]
    assert_equal "chat_attachment", run.state.dig("image_source", "kind")
    assert_equal "pixel.png", run.state.dig("image_source", "filename")
  ensure
    restore_vision_service
  end

  test "fails when attachment is missing" do
    add_user_message("この画像を説明して")

    run = AgentGraph::ImageUnderstandingGraphRunner.call(@chat)

    assert_predicate run, :failed?
    assert_match(/画像/, run.error_message)
    assert_equal [ "plan_image_understanding", "resolve_image_source" ], run.agent_node_runs.order(:id).pluck(:node_name)
  end

  test "fails for unsupported attachment content type" do
    message = add_user_message("この画像を説明して")
    message.attachments.attach(io: StringIO.new("text"), filename: "note.txt", content_type: "text/plain")

    run = AgentGraph::ImageUnderstandingGraphRunner.call(@chat)

    assert_predicate run, :failed?
    assert_match(/対応していない画像形式/, run.error_message)
    assert_equal "UNSUPPORTED_IMAGE_CONTENT_TYPE", run.state.dig("errors", 0, "code")
  end

  private

  def add_user_message(content)
    Message.suppressing_turbo_broadcasts do
      @chat.messages.create!(role: :user, content: content)
    end
  end

  def stub_vision_service(result)
    @original_vision_new = VisionChatService.method(:new)
    service = Object.new
    service.define_singleton_method(:analyze) do |image:, mime_type:, prompt:|
      raise "missing image" if image.blank?
      raise "missing mime_type" if mime_type.blank?
      raise "missing prompt" if prompt.blank?

      result
    end
    VisionChatService.define_singleton_method(:new) { service }
  end

  def restore_vision_service
    return unless @original_vision_new

    original = @original_vision_new
    VisionChatService.define_singleton_method(:new) { |**kwargs| original.call(**kwargs) }
  end
end
