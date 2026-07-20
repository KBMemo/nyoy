# frozen_string_literal: true

require "test_helper"

class LlamaServerAlertPolicyTest < ActiveSupport::TestCase
  test "does not notify for the initial healthy result" do
    assert_not policy_for(create_reconciliation("healthy")).notify?
  end

  test "notifies for the initial warning" do
    warning = create_reconciliation("warning", findings: [ finding("server_not_ready") ])

    assert policy_for(warning).notify?
    assert_equal "warning", policy_for(warning).event
  end

  test "suppresses an unchanged warning" do
    create_reconciliation("warning", findings: [ finding("server_not_ready") ])
    warning = create_reconciliation("warning", findings: [ finding("server_not_ready") ])

    assert_not policy_for(warning).notify?
  end

  test "notifies when warning identity changes" do
    create_reconciliation("warning", findings: [ finding("server_not_ready") ])
    warning = create_reconciliation("warning", findings: [ finding("alias_drift") ])

    assert policy_for(warning).notify?
  end

  test "notifies once for failed status and recovery" do
    create_reconciliation("warning", findings: [ finding("server_not_ready") ])
    failed = create_reconciliation("failed")
    repeated_failure = create_reconciliation("failed")
    recovered = create_reconciliation("healthy")

    assert policy_for(failed).notify?
    assert_not policy_for(repeated_failure).notify?
    assert policy_for(recovered).notify?
    assert_equal "recovered", policy_for(recovered).event
  end

  private

  def policy_for(reconciliation)
    LlamaServerAlertPolicy.new(reconciliation)
  end

  def create_reconciliation(status, findings: [])
    service_connections(:llama_switchd).llama_server_reconciliations.create!(
      status: status,
      findings: findings,
      checked_at: Time.current + LlamaServerReconciliation.count.seconds
    )
  end

  def finding(code)
    { "code" => code, "connection_key" => "llama_cpp", "server_id" => "main" }
  end
end
