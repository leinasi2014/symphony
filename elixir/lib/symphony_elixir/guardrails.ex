defmodule SymphonyElixir.Guardrails do
  @moduledoc """
  Pure helpers for Phase 1 guardrail policy evaluation.
  """

  alias SymphonyElixir.Linear.Issue

  @type issue_guardrails :: %{
          optional(:executable_labels) => [String.t()],
          optional(:blocked_labels) => [String.t()]
        }

  @spec executable_issue?(Issue.t(), issue_guardrails()) :: boolean()
  def executable_issue?(issue, guardrails \\ %{})

  def executable_issue?(%Issue{} = issue, guardrails) do
    issue_labels = MapSet.new(normalize_labels(Issue.label_names(issue)))
    blocked_labels = MapSet.new(normalize_labels(Map.get(guardrails, :blocked_labels, [])))
    executable_labels = normalize_labels(Map.get(guardrails, :executable_labels, []))

    blocked? = not MapSet.disjoint?(issue_labels, blocked_labels)

    executable? =
      case executable_labels do
        [] ->
          true

        labels ->
          not MapSet.disjoint?(issue_labels, MapSet.new(labels))
      end

    not blocked? and executable?
  end

  def executable_issue?(_issue, _guardrails), do: false

  @spec normalize_labels([term()]) :: [String.t()]
  def normalize_labels(labels) when is_list(labels) do
    labels
    |> Enum.map(&normalize_label/1)
    |> Enum.reject(&(&1 == ""))
  end

  def normalize_labels(_labels), do: []

  @spec normalize_label(term()) :: String.t()
  def normalize_label(label) when is_binary(label) do
    label
    |> String.trim()
    |> String.downcase()
  end

  def normalize_label(label) when is_atom(label), do: normalize_label(Atom.to_string(label))
  def normalize_label(label), do: label |> to_string() |> normalize_label()
end
