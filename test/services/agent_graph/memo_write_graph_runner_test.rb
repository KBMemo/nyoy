# frozen_string_literal: true

require "test_helper"

class AgentGraphMemoWriteGraphRunnerTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
    @chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
    @chat.messages.create!(role: :assistant, content: "# 今日のメモ\n\n内容の本体です。")
    @chat.messages.create!(role: :user, content: "これを徒然に保存して")
  end

  test "awaits approval then creates memo on approve" do
    stub_create_memo(uid: "01JMEMOWRITE") do
      run = AgentGraph::MemoWriteGraphRunner.call(@chat)

      assert run.awaiting_approval?, -> { "status=#{run.status} error=#{run.error_message}" }
      assert_equal "pending", run.state["approval"]
      assert_nil run.state["memo_uid"]
      assert run.state["draft"].present?
      assert_equal "今日のメモ", run.state.dig("memo_draft", "title")
      assert_includes run.state.dig("memo_draft", "body"), "内容の本体"
      assert_equal "memo_writer", run.state.dig("memo_draft_meta", "role")
      assert_equal "deterministic", run.state.dig("memo_draft_meta", "profile")

      completed = AgentGraph::MemoWriteGraphRunner.resume(run, decision: "approved")
      assert completed.completed?, -> { completed.error_message }
      assert_equal "01JMEMOWRITE", completed.state["memo_uid"]
      assert_includes completed.state["final_answer"], "01JMEMOWRITE"

      message = @chat.messages.where(role: :assistant).order(:id).last
      assert_includes message.content, "徒然に保存しました"
    end
  end

  test "reject ends without creating memo" do
    stub_create_memo(uid: "01NOPE") do
      run = AgentGraph::MemoWriteGraphRunner.call(@chat)
      assert run.awaiting_approval?

      completed = AgentGraph::MemoWriteGraphRunner.resume(run, decision: "rejected")
      assert completed.completed?
      assert_nil completed.state["memo_uid"]
      assert_includes completed.state["final_answer"], "却下"
      refute_includes completed.agent_node_runs.pluck(:node_name), "commit_memo"
    end
  end

  test "auto_approve creates without interrupt" do
    stub_create_memo(uid: "01AUTO") do
      run = AgentGraph::MemoWriteGraphRunner.call(@chat, auto_approve: true)

      assert run.completed?, -> { "status=#{run.status} error=#{run.error_message}" }
      assert_equal "approved", run.state["approval"]
      assert_equal "01AUTO", run.state["memo_uid"]
      assert_includes run.agent_node_runs.pluck(:node_name), "await_approval"
      assert_includes run.agent_node_runs.pluck(:node_name), "commit_memo"
      refute run.awaiting_approval?
    end
  end

  test "commit is idempotent when memo_uid already set" do
    stub_create_memo(uid: "01ONCE") do
      run = AgentGraph::MemoWriteGraphRunner.call(@chat)
      completed = AgentGraph::MemoWriteGraphRunner.resume(run, decision: "approved")
      assert_equal "01ONCE", completed.state["memo_uid"]

      node = AgentGraph::Nodes::MemoWrite::CommitMemo.new
      result = node.call(
        state: completed.state.merge("memo_uid" => "01ONCE"),
        run: completed,
        chat: @chat
      )
      refute result.explicit_goto?
      assert_equal "finalize_reply", AgentGraph::MemoWriteGraph.new.next_node_for("commit_memo", completed.state)
    end
  end

  test "fails when there is nothing to save" do
    @chat.messages.destroy_all
    @chat.messages.create!(role: :user, content: "これを徒然に保存して")

    run = AgentGraph::MemoWriteGraphRunner.call(@chat)
    assert run.failed?
    assert_match(/保存する内容/, run.error_message)
  end

  test "uses instruction leftover when no assistant message" do
    @chat.messages.destroy_all
    @chat.messages.create!(role: :user, content: "買い物リスト\n- 牛乳\nをメモにして")

    stub_create_memo(uid: "01INSTR") do
      run = AgentGraph::MemoWriteGraphRunner.call(@chat, auto_approve: true)
      assert run.completed?, -> { run.error_message }
      assert_includes run.state.dig("memo_draft", "body"), "牛乳"
    end
  end

  test "supersedes older pending memo write approvals" do
    old = AgentRun.create!(
      chat: @chat,
      graph_name: "memo_write",
      status: "awaiting_approval",
      current_node: "await_approval",
      state: { "approval" => "pending", "draft" => "old" }
    )

    stub_create_memo(uid: "01NEW") do
      AgentGraph::MemoWriteGraphRunner.call(@chat, auto_approve: true)
    end

    assert_equal "cancelled", old.reload.status
  end

  private

  def stub_create_memo(uid:)
    original = ChatTools::CreateMemo.instance_method(:execute)
    ChatTools::CreateMemo.define_method(:execute) do |body:, title: nil, tags: nil|
      { "uid" => uid, "title" => title, "body" => body, "updated_at" => Time.current.iso8601 }
    end
    yield
  ensure
    ChatTools::CreateMemo.define_method(:execute, original)
  end
end
