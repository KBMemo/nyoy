# frozen_string_literal: true

require "test_helper"

class AgentGraphMemoUpdateGraphRunnerTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
    @chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
    @chat.messages.create!(role: :user, content: "メモ 42 に追記して\n追記本文")
  end

  test "auto approve appends to memo" do
    stub_get_memo do
      stub_update_memo(uid: "42") do |calls|
        run = AgentGraph::MemoUpdateGraphRunner.call(@chat, auto_approve: true)

        assert run.completed?, -> { run.error_message }
        assert_equal "42", run.state["memo_uid"]
        assert_equal "42", calls.first[:memo_ref]
        assert_equal "2026-07-16T00:00:00Z", calls.first[:updated_at]
        assert_equal "追記本文", calls.first[:append_body]
        assert_nil calls.first[:body]
        assert_equal "memo_writer", run.state.dig("memo_draft_meta", "role")
        assert_equal "deterministic", run.state.dig("memo_draft_meta", "profile")
      end
    end
  end

  test "awaits approval then resumes" do
    stub_get_memo do
      stub_update_memo(uid: "42") do
        run = AgentGraph::MemoUpdateGraphRunner.call(@chat)

        assert run.awaiting_approval?
        assert_includes run.agent_node_runs.pluck(:node_name), "await_approval"

        completed = AgentGraph::MemoUpdateGraphRunner.resume(run, decision: "approved")

        assert completed.completed?, -> { completed.error_message }
        assert_equal "approved", completed.state["approval"]
      end
    end
  end

  test "reject ends without update" do
    stub_get_memo do
      calls = []
      original = ChatTools::UpdateMemo.instance_method(:execute)
      ChatTools::UpdateMemo.define_method(:execute) do |**kwargs|
        calls << kwargs
        { "uid" => "42" }
      end

      run = AgentGraph::MemoUpdateGraphRunner.call(@chat)
      completed = AgentGraph::MemoUpdateGraphRunner.resume(run, decision: "rejected")

      assert completed.completed?
      assert_equal "rejected", completed.state["approval"]
      assert_empty calls
    ensure
      ChatTools::UpdateMemo.define_method(:execute, original) if defined?(original)
    end
  end

  test "fails when memo ref is missing" do
    @chat.messages.destroy_all
    @chat.messages.create!(role: :user, content: "メモに追記して\n本文")

    run = AgentGraph::MemoUpdateGraphRunner.call(@chat, auto_approve: true)

    assert run.failed?
    assert_match(/更新対象/, run.error_message)
  end

  private

  def stub_get_memo
    original = ChatTools::GetMemo.instance_method(:execute)
    ChatTools::GetMemo.define_method(:execute) do |memo_ref:|
      {
        "uid" => memo_ref,
        "title" => "既存メモ",
        "body" => "既存本文",
        "updated_at" => "2026-07-16T00:00:00Z"
      }
    end
    yield
  ensure
    ChatTools::GetMemo.define_method(:execute, original)
  end

  def stub_update_memo(uid:)
    calls = []
    original = ChatTools::UpdateMemo.instance_method(:execute)
    ChatTools::UpdateMemo.define_method(:execute) do |**kwargs|
      calls << kwargs
      { "uid" => uid, "title" => "既存メモ", "updated_at" => Time.current.iso8601 }
    end
    yield calls
  ensure
    ChatTools::UpdateMemo.define_method(:execute, original)
  end
end
