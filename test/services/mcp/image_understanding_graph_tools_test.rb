# frozen_string_literal: true

require "test_helper"

class McpImageUnderstandingGraphToolsTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
    @model = Model.find_by!(provider: "openai", model_id: "gpt-oss")
  end

  test "catalog includes image understanding graph tools" do
    tools = Mcp::ToolCatalog.tools(server_context: {
      web_budget: ChatTools::WebToolBudget.from_settings,
      tool_instances: {}
    })
    names = tools.map(&:name_value)

    assert_includes names, "run_image_understanding_graph"
    assert_includes names, "get_image_understanding_graph"
    assert_includes names, "retry_image_understanding_graph"
    refute_includes names, "resume_image_understanding_graph"
  end

  test "run_image_understanding_graph uses chat attachment" do
    chat = chat_with_attachment(content: "この画像を説明して")

    stub_vision_service("画像には看板が写っています。") do
      response = Mcp::ImageUnderstandingGraphTools.run_image_understanding_graph_tool.call(
        question: "この画像を説明して",
        chat_id: chat.id
      )
      payload = JSON.parse(response.content.first[:text])

      assert_not response.error?
      assert_equal "completed", payload["status"]
      assert_equal "画像には看板が写っています。", payload["analysis"]
      assert_equal "画像には看板が写っています。", payload["final_answer"]
      assert_equal "chat_attachment", payload.dig("image_source", "kind")
      assert_includes payload["nodes"], "analyze_image"
    end
  end

  test "get_image_understanding_graph returns summary" do
    chat = chat_with_attachment(content: "この画像には何が写っていますか？")

    stub_vision_service("山道が写っています。") do
      run = AgentGraph::ImageUnderstandingGraphRunner.call(chat)
      response = Mcp::ImageUnderstandingGraphTools.get_image_understanding_graph_tool.call(agent_run_id: run.id)
      payload = JSON.parse(response.content.first[:text])

      assert_equal run.id, payload["agent_run_id"]
      assert_equal "completed", payload["status"]
      assert_equal "山道が写っています。", payload["analysis"]
    end
  end

  test "get_image_understanding_graph errors for missing id" do
    response = Mcp::ImageUnderstandingGraphTools.get_image_understanding_graph_tool.call(agent_run_id: 0)

    assert response.error?
    payload = JSON.parse(response.content.first[:text])
    assert payload["error"].present?
  end

  test "retry_image_understanding_graph launches duplicate run" do
    chat = chat_with_attachment(content: "この画像を説明して")
    attachment = chat.messages.where(role: :user).last.attachments.first
    state = {
      "question" => "この画像を説明して",
      "chat_id" => chat.id,
      "intent" => "image_understanding",
      "plan" => { "message_id" => attachment.record_id, "attachment_index" => 0 },
      "image_source" => {
        "kind" => "chat_attachment",
        "message_id" => attachment.record_id,
        "attachment_id" => attachment.id,
        "attachment_index" => 0,
        "filename" => attachment.filename.to_s,
        "content_type" => attachment.content_type,
        "byte_size" => attachment.byte_size
      },
      "analysis" => nil,
      "final_answer" => nil,
      "approval" => "not_required",
      "auto_approve" => true,
      "errors" => [],
      "next_node" => "analyze_image"
    }
    run = AgentRun.create!(
      chat: chat,
      graph_name: AgentGraph::ImageUnderstandingGraph::NAME,
      status: "failed",
      current_node: "analyze_image",
      state: state,
      error_message: "vision failed"
    )
    completed = run.agent_node_runs.create!(
      node_name: "resolve_image_source",
      status: "completed",
      started_at: 2.minutes.ago,
      finished_at: 1.minute.ago
    )
    checkpoint = run.agent_checkpoints.create!(
      node_name: completed.node_name,
      state: state,
      created_at: completed.finished_at + 1.second
    )
    run.agent_node_runs.create!(node_name: "analyze_image", status: "failed")

    stub_vision_service("再解析できました。") do
      response = Mcp::ImageUnderstandingGraphTools.retry_image_understanding_graph_tool.call(agent_run_id: run.id)
      payload = JSON.parse(response.content.first[:text])

      assert_not response.error?
      assert_equal "completed", payload["status"]
      assert_not_equal run.id, payload["agent_run_id"]
      assert_equal "再解析できました。", payload["analysis"]
      retry_run = AgentRun.find(payload["agent_run_id"])
      assert_equal run.id, retry_run.state["retry_of_agent_run_id"]
      assert_equal checkpoint.id, retry_run.state["retry_from_checkpoint_id"]
      assert_equal "resolve_image_source", retry_run.state["retry_from_node"]
    end
  end

  private

  def chat_with_attachment(content:)
    chat = Chat.create!(model: @model)
    Message.suppressing_turbo_broadcasts do
      message = chat.messages.create!(role: :user, content: content)
      message.attachments.attach(io: StringIO.new("png"), filename: "pixel.png", content_type: "image/png")
    end
    chat
  end

  def stub_vision_service(result)
    original = VisionChatService.method(:new)
    service = Object.new
    service.define_singleton_method(:analyze) do |image:, mime_type:, prompt:|
      raise "missing image" if image.blank?
      raise "missing mime_type" if mime_type.blank?
      raise "missing prompt" if prompt.blank?

      result
    end
    VisionChatService.define_singleton_method(:new) { service }
    yield
  ensure
    VisionChatService.define_singleton_method(:new) { |**kwargs| original.call(**kwargs) } if original
  end
end
