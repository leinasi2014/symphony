defmodule SymphonyElixir.AgentRunner do
  @moduledoc """
  Executes a single Linear issue in an isolated workspace with Codex.
  """

  require Logger
  alias SymphonyElixir.Codex.AppServer
  alias SymphonyElixir.{Config, Linear.Issue, Orchestrator, PromptBuilder, Tracker, Workspace, WorkspaceProgress}

  @spec run(map(), pid() | nil, keyword()) :: :ok | no_return()
  def run(issue, codex_update_recipient \\ nil, opts \\ []) do
    Logger.info("Starting agent run for #{issue_context(issue)}")

    case Workspace.create_for_issue(issue) do
      {:ok, workspace} ->
        try do
          with :ok <- Workspace.run_before_run_hook(workspace, issue),
               :ok <- send_workspace_ready(codex_update_recipient, issue, workspace),
               :ok <- run_codex_turns(workspace, issue, codex_update_recipient, opts) do
            :ok
          else
            {:error, reason} ->
              Logger.error("Agent run failed for #{issue_context(issue)}: #{inspect(reason)}")
              raise RuntimeError, "Agent run failed for #{issue_context(issue)}: #{inspect(reason)}"
          end
        after
          Workspace.run_after_run_hook(workspace, issue)
        end

      {:error, reason} ->
        Logger.error("Agent run failed for #{issue_context(issue)}: #{inspect(reason)}")
        raise RuntimeError, "Agent run failed for #{issue_context(issue)}: #{inspect(reason)}"
    end
  end

  defp codex_message_handler(recipient, issue) do
    fn message ->
      send_codex_update(recipient, issue, message)
    end
  end

  defp send_codex_update(recipient, %Issue{id: issue_id}, message)
       when is_binary(issue_id) and is_pid(recipient) do
    send(recipient, {:codex_worker_update, issue_id, message})
    :ok
  end

  defp send_codex_update(_recipient, _issue, _message), do: :ok

  defp send_workspace_ready(recipient, %Issue{id: issue_id}, workspace)
       when is_binary(issue_id) and is_pid(recipient) and is_binary(workspace) do
    fingerprint =
      case WorkspaceProgress.capture(workspace) do
        {:ok, fingerprint} -> fingerprint
        {:error, _reason} -> nil
      end

    send(recipient, {
      :codex_worker_update,
      issue_id,
      %{
        event: :workspace_ready,
        workspace: workspace,
        progress_fingerprint: fingerprint,
        timestamp: DateTime.utc_now()
      }
    })

    :ok
  end

  defp send_workspace_ready(_recipient, _issue, _workspace), do: :ok

  defp run_codex_turns(workspace, issue, codex_update_recipient, opts) do
    max_turns = Keyword.get(opts, :max_turns, Config.agent_max_turns())
    issue_state_fetcher = Keyword.get(opts, :issue_state_fetcher, &Tracker.fetch_issue_states_by_ids/1)

    continuation_decider =
      Keyword.get(
        opts,
        :continuation_decider,
        default_continuation_decider(codex_update_recipient, issue_state_fetcher)
      )

    with {:ok, session} <- AppServer.start_session(workspace) do
      try do
        do_run_codex_turns(
          session,
          workspace,
          issue,
          codex_update_recipient,
          opts,
          continuation_decider,
          1,
          max_turns
        )
      after
        AppServer.stop_session(session)
      end
    end
  end

  defp do_run_codex_turns(
         app_session,
         workspace,
         issue,
         codex_update_recipient,
         opts,
         continuation_decider,
         turn_number,
         max_turns
       ) do
    prompt = build_turn_prompt(issue, opts, turn_number, max_turns)

    with {:ok, turn_session} <-
           AppServer.run_turn(
             app_session,
             prompt,
             issue,
             on_message: codex_message_handler(codex_update_recipient, issue)
           ) do
      Logger.info("Completed agent run for #{issue_context(issue)} session_id=#{turn_session[:session_id]} workspace=#{workspace} turn=#{turn_number}/#{max_turns}")

      case continuation_decider.(issue, turn_number) do
        {:allow, _mode, %Issue{} = refreshed_issue} when turn_number < max_turns ->
          Logger.info("Continuing agent run for #{issue_context(refreshed_issue)} after orchestrator approval turn=#{turn_number}/#{max_turns}")

          do_run_codex_turns(
            app_session,
            workspace,
            refreshed_issue,
            codex_update_recipient,
            opts,
            continuation_decider,
            turn_number + 1,
            max_turns
          )

        {:allow, _mode, %Issue{} = refreshed_issue} ->
          Logger.info("Reached agent.max_turns for #{issue_context(refreshed_issue)} with issue still active; returning control to orchestrator")

          :ok

        {:deny, _reason} ->
          :ok

        :unavailable ->
          :ok

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp build_turn_prompt(issue, opts, 1, _max_turns), do: PromptBuilder.build_prompt(issue, opts)

  defp build_turn_prompt(_issue, _opts, turn_number, max_turns) do
    """
    Continuation guidance:

    - The previous Codex turn completed normally, but the Linear issue is still in an active state.
    - This is continuation turn ##{turn_number} of #{max_turns} for the current agent run.
    - Resume from the current workspace and workpad state instead of restarting from scratch.
    - The original task instructions and prior turn context are already present in this thread, so do not restate them before acting.
    - Focus on the remaining ticket work and do not end the turn while the issue stays active unless you are truly blocked.
    """
  end

  defp default_continuation_decider(recipient, issue_state_fetcher) when is_pid(recipient) do
    fn
      %Issue{id: issue_id}, turn_number when is_binary(issue_id) ->
        Orchestrator.request_continuation(recipient, issue_id, turn_number)

      issue, _turn_number ->
        fallback_continuation_decision(issue, issue_state_fetcher)
    end
  end

  defp default_continuation_decider(_recipient, issue_state_fetcher) do
    fn issue, _turn_number ->
      fallback_continuation_decision(issue, issue_state_fetcher)
    end
  end

  defp fallback_continuation_decision(%Issue{id: issue_id}, issue_state_fetcher)
       when is_binary(issue_id) do
    case issue_state_fetcher.([issue_id]) do
      {:ok, [%Issue{} = refreshed_issue | _]} ->
        if active_issue_state?(refreshed_issue.state) do
          {:allow, :default, refreshed_issue}
        else
          {:deny, :issue_not_active}
        end

      {:ok, []} ->
        {:deny, :issue_missing}

      {:error, reason} ->
        {:error, {:issue_state_refresh_failed, reason}}
    end
  end

  defp fallback_continuation_decision(_issue, _issue_state_fetcher), do: {:deny, :issue_not_active}

  defp active_issue_state?(state_name) when is_binary(state_name) do
    normalized_state = normalize_issue_state(state_name)

    Config.linear_active_states()
    |> Enum.any?(fn active_state -> normalize_issue_state(active_state) == normalized_state end)
  end

  defp active_issue_state?(_state_name), do: false

  defp normalize_issue_state(state_name) when is_binary(state_name) do
    state_name
    |> String.trim()
    |> String.downcase()
  end

  defp issue_context(%Issue{id: issue_id, identifier: identifier}) do
    "issue_id=#{issue_id} issue_identifier=#{identifier}"
  end
end
