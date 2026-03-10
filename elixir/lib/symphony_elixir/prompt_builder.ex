defmodule SymphonyElixir.PromptBuilder do
  @moduledoc """
  Builds agent prompts from Linear issue data.
  """

  alias SymphonyElixir.{Config, Workflow}

  @render_opts [strict_variables: true, strict_filters: true]
  @type prompt_mode :: :initial | :continuation_summary

  @spec build_prompt(SymphonyElixir.Linear.Issue.t(), keyword()) :: String.t()
  def build_prompt(issue, opts \\ []) do
    case Keyword.get(opts, :prompt_mode, :initial) do
      :initial ->
        build_initial_prompt(issue, opts)

      :continuation_summary ->
        build_continuation_summary_prompt(issue, opts)

      prompt_mode ->
        raise ArgumentError, "unsupported_prompt_mode: #{inspect(prompt_mode)}"
    end
  end

  defp build_initial_prompt(issue, opts) do
    template =
      Workflow.current()
      |> prompt_template!()
      |> parse_template!()

    template
    |> Solid.render!(
      %{
        "attempt" => Keyword.get(opts, :attempt),
        "issue" => issue |> Map.from_struct() |> to_solid_map()
      },
      @render_opts
    )
    |> IO.iodata_to_binary()
  end

  defp build_continuation_summary_prompt(issue, opts) do
    initial_prompt = build_initial_prompt(issue, opts)
    issue_identifier = issue.identifier || "unknown"
    issue_title = issue.title || "Untitled"
    issue_state = issue.state || "unknown"
    issue_description = issue.description || "No description provided."
    turn_number = Keyword.get(opts, :turn_number)
    max_turns = Keyword.get(opts, :max_turns)
    context_summary_path = Keyword.get(opts, :context_summary_path, Path.join("shared", "context_summary.md"))
    guardrail_state_path = Keyword.get(opts, :guardrail_state_path, Path.join("shared", "guardrail_state.json"))

    """
    #{initial_prompt}

    Fresh-session continuation summary:

    - Issue: #{issue_identifier} #{issue_title}
    - Current Linear state: #{issue_state}
    - Continuation turn ##{turn_number} of #{max_turns}
    - Do not assume the full prior thread history is available in this session.
    - Resume from the current workspace state and read these artifacts before acting:
      - `#{context_summary_path}`
      - `#{guardrail_state_path}`
    - Continue only the remaining ticket work. Do not restart from scratch.

    Issue description:
    #{issue_description}
    """
    |> String.trim()
  end

  defp prompt_template!({:ok, %{prompt_template: prompt}}), do: default_prompt(prompt)

  defp prompt_template!({:error, reason}) do
    raise RuntimeError, "workflow_unavailable: #{inspect(reason)}"
  end

  defp parse_template!(prompt) when is_binary(prompt) do
    Solid.parse!(prompt)
  rescue
    error ->
      reraise %RuntimeError{
                message: "template_parse_error: #{Exception.message(error)} template=#{inspect(prompt)}"
              },
              __STACKTRACE__
  end

  defp to_solid_map(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), to_solid_value(value)} end)
  end

  defp to_solid_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp to_solid_value(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp to_solid_value(%Date{} = value), do: Date.to_iso8601(value)
  defp to_solid_value(%Time{} = value), do: Time.to_iso8601(value)
  defp to_solid_value(%_{} = value), do: value |> Map.from_struct() |> to_solid_map()
  defp to_solid_value(value) when is_map(value), do: to_solid_map(value)
  defp to_solid_value(value) when is_list(value), do: Enum.map(value, &to_solid_value/1)
  defp to_solid_value(value), do: value

  defp default_prompt(prompt) when is_binary(prompt) do
    if String.trim(prompt) == "" do
      Config.workflow_prompt()
    else
      prompt
    end
  end
end
