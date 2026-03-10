defmodule SymphonyElixir.GuardrailsTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.Guardrails
  alias SymphonyElixir.Linear.Issue

  test "executable_issue? allows issues when executable labels are disabled" do
    issue = %Issue{labels: ["meta"]}

    assert Guardrails.executable_issue?(issue, %{
             executable_labels: [],
             blocked_labels: []
           })
  end

  test "executable_issue? rejects issues with blocked labels" do
    issue = %Issue{labels: ["exec-ready", "meta"]}

    refute Guardrails.executable_issue?(issue, %{
             executable_labels: ["exec-ready"],
             blocked_labels: ["meta", "manual-env"]
           })
  end

  test "executable_issue? normalizes configured and issue labels" do
    issue = %Issue{labels: [" Exec-Ready "]}

    assert Guardrails.executable_issue?(issue, %{
             executable_labels: ["exec-ready"],
             blocked_labels: ["meta"]
           })
  end

  test "executable_issue? refuses issues that do not match any executable label" do
    issue = %Issue{labels: ["meta"]}

    refute Guardrails.executable_issue?(issue, %{
             executable_labels: ["exec-ready"],
             blocked_labels: ["manual-env"]
           })
  end
end
