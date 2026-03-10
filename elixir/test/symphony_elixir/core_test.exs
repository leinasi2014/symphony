defmodule SymphonyElixir.CoreTest do
  use SymphonyElixir.TestSupport

  test "config defaults and validation checks" do
    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_api_token: nil,
      tracker_project_slug: nil,
      poll_interval_ms: nil,
      tracker_active_states: nil,
      tracker_terminal_states: nil,
      codex_command: nil
    )

    assert Config.poll_interval_ms() == 30_000
    assert Config.linear_active_states() == ["Todo", "In Progress"]
    assert Config.linear_terminal_states() == ["Closed", "Cancelled", "Canceled", "Duplicate", "Done"]
    assert Config.linear_assignee() == nil
    assert Config.agent_max_turns() == 20
    refute Config.guardrails_enabled?()
    assert Config.guardrails_mode() == "observe"
    assert Config.guardrails_stop_state() == nil
    assert Config.guardrails_create_comment_on_stop?()
    assert Config.guardrails_warning_cooldown_seconds() == 60
    assert Config.guardrails_executable_labels() == []
    assert Config.guardrails_blocked_labels() == ["meta", "split-before-run", "manual-env"]

    assert Config.guardrails_probe_budget() == %{
             max_total_turns_per_issue: 1,
             soft_total_tokens: 25_000,
             hard_total_tokens: 50_000,
             soft_input_tokens: 20_000,
             hard_input_tokens: 40_000
           }

    assert Config.guardrails_default_budget() == %{
             max_total_turns_per_issue: 3,
             max_continuation_runs_per_issue: 2,
             no_progress_turn_limit: 1,
             soft_total_tokens: 120_000,
             hard_total_tokens: 180_000,
             soft_input_tokens: 100_000,
             hard_input_tokens: 150_000
           }

    write_workflow_file!(Workflow.workflow_file_path(), poll_interval_ms: "invalid")
    assert Config.poll_interval_ms() == 30_000

    write_workflow_file!(Workflow.workflow_file_path(), poll_interval_ms: 45_000)
    assert Config.poll_interval_ms() == 45_000

    write_workflow_file!(Workflow.workflow_file_path(), max_turns: 0)
    assert Config.agent_max_turns() == 20

    write_workflow_file!(Workflow.workflow_file_path(), max_turns: 5)
    assert Config.agent_max_turns() == 5

    write_workflow_file!(Workflow.workflow_file_path(), tracker_active_states: "Todo,  Review,")
    assert Config.linear_active_states() == ["Todo", "Review"]

    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_api_token: "token",
      tracker_project_slug: nil
    )

    assert {:error, :missing_linear_project_slug} = Config.validate!()

    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_project_slug: "project",
      codex_command: ""
    )

    assert :ok = Config.validate!()

    write_workflow_file!(Workflow.workflow_file_path(), codex_command: "/bin/sh app-server")
    assert :ok = Config.validate!()

    write_workflow_file!(Workflow.workflow_file_path(), codex_approval_policy: "definitely-not-valid")
    assert :ok = Config.validate!()

    write_workflow_file!(Workflow.workflow_file_path(), codex_thread_sandbox: "unsafe-ish")
    assert :ok = Config.validate!()

    write_workflow_file!(Workflow.workflow_file_path(),
      codex_turn_sandbox_policy: %{type: "workspaceWrite", writableRoots: ["relative/path"]}
    )

    assert :ok = Config.validate!()

    write_workflow_file!(Workflow.workflow_file_path(), codex_approval_policy: 123)
    assert {:error, {:invalid_codex_approval_policy, 123}} = Config.validate!()

    write_workflow_file!(Workflow.workflow_file_path(), codex_thread_sandbox: 123)
    assert {:error, {:invalid_codex_thread_sandbox, 123}} = Config.validate!()

    write_workflow_file!(Workflow.workflow_file_path(), tracker_kind: 123)
    assert {:error, {:unsupported_tracker_kind, "123"}} = Config.validate!()
  end

  test "guardrails config getters resolve from workflow front matter" do
    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_project_slug: "project",
      codex_command: "/bin/sh app-server",
      agent_guardrails: %{
        enabled: true,
        mode: "enforce",
        stop_state: "Human Review",
        create_comment_on_stop: false,
        warning_cooldown_seconds: 45,
        executable_labels: [" exec-ready "],
        blocked_labels: ["meta", "manual-env"],
        probe: %{
          max_total_turns_per_issue: 2,
          soft_total_tokens: 10_000,
          hard_total_tokens: 20_000,
          soft_input_tokens: 8_000,
          hard_input_tokens: 16_000
        },
        default: %{
          max_total_turns_per_issue: 4,
          max_continuation_runs_per_issue: 3,
          no_progress_turn_limit: 0,
          soft_total_tokens: 200_000,
          hard_total_tokens: 240_000,
          soft_input_tokens: 180_000,
          hard_input_tokens: 220_000
        }
      }
    )

    assert Config.guardrails_enabled?()
    assert Config.guardrails_mode() == "enforce"
    assert Config.guardrails_stop_state() == "Human Review"
    refute Config.guardrails_create_comment_on_stop?()
    assert Config.guardrails_warning_cooldown_seconds() == 45
    assert Config.guardrails_executable_labels() == ["exec-ready"]
    assert Config.guardrails_blocked_labels() == ["meta", "manual-env"]

    assert Config.guardrails_probe_budget() == %{
             max_total_turns_per_issue: 2,
             soft_total_tokens: 10_000,
             hard_total_tokens: 20_000,
             soft_input_tokens: 8_000,
             hard_input_tokens: 16_000
           }

    assert Config.guardrails_default_budget() == %{
             max_total_turns_per_issue: 4,
             max_continuation_runs_per_issue: 3,
             no_progress_turn_limit: 0,
             soft_total_tokens: 200_000,
             hard_total_tokens: 240_000,
             soft_input_tokens: 180_000,
             hard_input_tokens: 220_000
           }

    assert :ok = Config.validate!()
  end

  test "guardrails validation rejects missing stop state active stop states and overlapping labels" do
    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_project_slug: "project",
      codex_command: "/bin/sh app-server",
      agent_guardrails: %{
        enabled: true
      }
    )

    assert {:error, :missing_guardrails_stop_state} = Config.validate!()

    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_project_slug: "project",
      codex_command: "/bin/sh app-server",
      agent_guardrails: %{
        enabled: true,
        mode: "banana",
        stop_state: "Human Review"
      }
    )

    assert {:error, {:invalid_guardrails_mode, "banana"}} = Config.validate!()

    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_project_slug: "project",
      codex_command: "/bin/sh app-server",
      tracker_active_states: ["Todo", "Human Review"],
      agent_guardrails: %{
        enabled: true,
        stop_state: "Human Review"
      }
    )

    assert {:error, {:guardrails_stop_state_is_active, "Human Review"}} = Config.validate!()

    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_project_slug: "project",
      codex_command: "/bin/sh app-server",
      agent_guardrails: %{
        enabled: true,
        stop_state: "Human Review",
        executable_labels: ["Exec-Ready", "meta "],
        blocked_labels: [" meta", "manual-env"]
      }
    )

    assert {:error, {:guardrails_label_overlap, ["meta"]}} = Config.validate!()
  end

  test "current WORKFLOW.md file is valid and complete" do
    original_workflow_path = Workflow.workflow_file_path()
    on_exit(fn -> Workflow.set_workflow_file_path(original_workflow_path) end)
    Workflow.clear_workflow_file_path()

    assert {:ok, %{config: config, prompt: prompt}} = Workflow.load()
    assert is_map(config)

    tracker = Map.get(config, "tracker", %{})
    assert is_map(tracker)
    assert Map.get(tracker, "kind") == "linear"
    assert is_binary(Map.get(tracker, "project_slug"))
    assert is_list(Map.get(tracker, "active_states"))
    assert is_list(Map.get(tracker, "terminal_states"))

    hooks = Map.get(config, "hooks", %{})
    assert is_map(hooks)
    assert Map.get(hooks, "after_create") =~ "git clone --depth 1 https://github.com/openai/symphony ."
    assert Map.get(hooks, "after_create") =~ "cd elixir && mise trust"
    assert Map.get(hooks, "after_create") =~ "mise exec -- mix deps.get"
    assert Map.get(hooks, "before_remove") =~ "cd elixir && mise exec -- mix workspace.before_remove"

    assert String.trim(prompt) != ""
    assert is_binary(Config.workflow_prompt())
    assert Config.workflow_prompt() == prompt
  end

  test "linear api token resolves from LINEAR_API_KEY env var" do
    previous_linear_api_key = System.get_env("LINEAR_API_KEY")
    env_api_key = "test-linear-api-key"

    on_exit(fn -> restore_env("LINEAR_API_KEY", previous_linear_api_key) end)
    System.put_env("LINEAR_API_KEY", env_api_key)

    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_api_token: nil,
      tracker_project_slug: "project",
      codex_command: "/bin/sh app-server"
    )

    assert Config.linear_api_token() == env_api_key
    assert Config.linear_project_slug() == "project"
    assert :ok = Config.validate!()
  end

  test "linear assignee resolves from LINEAR_ASSIGNEE env var" do
    previous_linear_assignee = System.get_env("LINEAR_ASSIGNEE")
    env_assignee = "dev@example.com"

    on_exit(fn -> restore_env("LINEAR_ASSIGNEE", previous_linear_assignee) end)
    System.put_env("LINEAR_ASSIGNEE", env_assignee)

    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_assignee: nil,
      tracker_project_slug: "project",
      codex_command: "/bin/sh app-server"
    )

    assert Config.linear_assignee() == env_assignee
  end

  test "workflow file path defaults to WORKFLOW.md in the current working directory when app env is unset" do
    original_workflow_path = Workflow.workflow_file_path()

    on_exit(fn ->
      Workflow.set_workflow_file_path(original_workflow_path)
    end)

    Workflow.clear_workflow_file_path()

    assert Workflow.workflow_file_path() == Path.join(File.cwd!(), "WORKFLOW.md")
  end

  test "workflow file path resolves from app env when set" do
    app_workflow_path = "/tmp/app/WORKFLOW.md"

    on_exit(fn ->
      Workflow.clear_workflow_file_path()
    end)

    Workflow.set_workflow_file_path(app_workflow_path)

    assert Workflow.workflow_file_path() == app_workflow_path
  end

  test "workflow load accepts prompt-only files without front matter" do
    workflow_path = Path.join(Path.dirname(Workflow.workflow_file_path()), "PROMPT_ONLY_WORKFLOW.md")
    File.write!(workflow_path, "Prompt only\n")

    assert {:ok, %{config: %{}, prompt: "Prompt only", prompt_template: "Prompt only"}} =
             Workflow.load(workflow_path)
  end

  test "workflow load accepts unterminated front matter with an empty prompt" do
    workflow_path = Path.join(Path.dirname(Workflow.workflow_file_path()), "UNTERMINATED_WORKFLOW.md")
    File.write!(workflow_path, "---\ntracker:\n  kind: linear\n")

    assert {:ok, %{config: %{"tracker" => %{"kind" => "linear"}}, prompt: "", prompt_template: ""}} =
             Workflow.load(workflow_path)
  end

  test "workflow load rejects non-map front matter" do
    workflow_path = Path.join(Path.dirname(Workflow.workflow_file_path()), "INVALID_FRONT_MATTER_WORKFLOW.md")
    File.write!(workflow_path, "---\n- not-a-map\n---\nPrompt body\n")

    assert {:error, :workflow_front_matter_not_a_map} = Workflow.load(workflow_path)
  end

  test "SymphonyElixir.start_link delegates to the orchestrator" do
    write_workflow_file!(Workflow.workflow_file_path(), tracker_kind: "memory")
    Application.put_env(:symphony_elixir, :memory_tracker_issues, [])
    orchestrator_pid = Process.whereis(SymphonyElixir.Orchestrator)

    on_exit(fn ->
      if is_nil(Process.whereis(SymphonyElixir.Orchestrator)) do
        case Supervisor.restart_child(SymphonyElixir.Supervisor, SymphonyElixir.Orchestrator) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
        end
      end
    end)

    if is_pid(orchestrator_pid) do
      assert :ok = Supervisor.terminate_child(SymphonyElixir.Supervisor, SymphonyElixir.Orchestrator)
    end

    assert {:ok, pid} = SymphonyElixir.start_link()
    assert Process.whereis(SymphonyElixir.Orchestrator) == pid

    GenServer.stop(pid)
  end

  test "linear issue state reconciliation fetch with no running issues is a no-op" do
    assert {:ok, []} = Client.fetch_issue_states_by_ids([])
  end

  test "non-active issue state stops running agent without cleaning workspace" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-nonactive-reconcile-#{System.unique_integer([:positive])}"
      )

    issue_id = "issue-1"
    issue_identifier = "MT-555"
    workspace = Path.join(test_root, issue_identifier)

    try do
      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: test_root,
        tracker_active_states: ["Todo", "In Progress", "In Review"],
        tracker_terminal_states: ["Closed", "Cancelled", "Canceled", "Duplicate"]
      )

      File.mkdir_p!(test_root)
      File.mkdir_p!(workspace)

      agent_pid =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      state = %Orchestrator.State{
        running: %{
          issue_id => %{
            pid: agent_pid,
            ref: nil,
            identifier: issue_identifier,
            issue: %Issue{id: issue_id, state: "Todo", identifier: issue_identifier},
            started_at: DateTime.utc_now()
          }
        },
        claimed: MapSet.new([issue_id]),
        codex_totals: %{input_tokens: 0, output_tokens: 0, total_tokens: 0, seconds_running: 0},
        retry_attempts: %{}
      }

      issue = %Issue{
        id: issue_id,
        identifier: issue_identifier,
        state: "Backlog",
        title: "Queued",
        description: "Not started",
        labels: []
      }

      updated_state = Orchestrator.reconcile_issue_states_for_test([issue], state)

      refute Map.has_key?(updated_state.running, issue_id)
      refute MapSet.member?(updated_state.claimed, issue_id)
      refute Process.alive?(agent_pid)
      assert File.exists?(workspace)
    after
      File.rm_rf(test_root)
    end
  end

  test "terminal issue state stops running agent and cleans workspace" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-terminal-reconcile-#{System.unique_integer([:positive])}"
      )

    issue_id = "issue-2"
    issue_identifier = "MT-556"
    workspace = Path.join(test_root, issue_identifier)

    try do
      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: test_root,
        tracker_active_states: ["Todo", "In Progress", "In Review"],
        tracker_terminal_states: ["Closed", "Cancelled", "Canceled", "Duplicate"]
      )

      File.mkdir_p!(test_root)
      File.mkdir_p!(workspace)

      agent_pid =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      state = %Orchestrator.State{
        running: %{
          issue_id => %{
            pid: agent_pid,
            ref: nil,
            identifier: issue_identifier,
            issue: %Issue{id: issue_id, state: "In Progress", identifier: issue_identifier},
            started_at: DateTime.utc_now()
          }
        },
        claimed: MapSet.new([issue_id]),
        codex_totals: %{input_tokens: 0, output_tokens: 0, total_tokens: 0, seconds_running: 0},
        retry_attempts: %{}
      }

      issue = %Issue{
        id: issue_id,
        identifier: issue_identifier,
        state: "Closed",
        title: "Done",
        description: "Completed",
        labels: []
      }

      updated_state = Orchestrator.reconcile_issue_states_for_test([issue], state)

      refute Map.has_key?(updated_state.running, issue_id)
      refute MapSet.member?(updated_state.claimed, issue_id)
      refute Process.alive?(agent_pid)
      refute File.exists?(workspace)
    after
      File.rm_rf(test_root)
    end
  end

  test "reconcile updates running issue state for active issues" do
    issue_id = "issue-3"

    state = %Orchestrator.State{
      running: %{
        issue_id => %{
          pid: self(),
          ref: nil,
          identifier: "MT-557",
          issue: %Issue{
            id: issue_id,
            identifier: "MT-557",
            state: "Todo"
          },
          started_at: DateTime.utc_now()
        }
      },
      claimed: MapSet.new([issue_id]),
      codex_totals: %{input_tokens: 0, output_tokens: 0, total_tokens: 0, seconds_running: 0},
      retry_attempts: %{}
    }

    issue = %Issue{
      id: issue_id,
      identifier: "MT-557",
      state: "In Progress",
      title: "Active state refresh",
      description: "State should be refreshed",
      labels: []
    }

    updated_state = Orchestrator.reconcile_issue_states_for_test([issue], state)
    updated_entry = updated_state.running[issue_id]

    assert Map.has_key?(updated_state.running, issue_id)
    assert MapSet.member?(updated_state.claimed, issue_id)
    assert updated_entry.issue.state == "In Progress"
  end

  test "reconcile stops running issue when it is reassigned away from this worker" do
    issue_id = "issue-reassigned"

    agent_pid =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    state = %Orchestrator.State{
      running: %{
        issue_id => %{
          pid: agent_pid,
          ref: nil,
          identifier: "MT-561",
          issue: %Issue{
            id: issue_id,
            identifier: "MT-561",
            state: "In Progress",
            assigned_to_worker: true
          },
          started_at: DateTime.utc_now()
        }
      },
      claimed: MapSet.new([issue_id]),
      codex_totals: %{input_tokens: 0, output_tokens: 0, total_tokens: 0, seconds_running: 0},
      retry_attempts: %{}
    }

    issue = %Issue{
      id: issue_id,
      identifier: "MT-561",
      state: "In Progress",
      title: "Reassigned active issue",
      description: "Worker should stop",
      labels: [],
      assigned_to_worker: false
    }

    updated_state = Orchestrator.reconcile_issue_states_for_test([issue], state)

    refute Map.has_key?(updated_state.running, issue_id)
    refute MapSet.member?(updated_state.claimed, issue_id)
    refute Process.alive?(agent_pid)
  end

  test "guardrails prevent dispatch for issues without executable labels or with blocked labels" do
    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_project_slug: "project",
      codex_command: "/bin/sh app-server",
      agent_guardrails: %{
        enabled: true,
        mode: "observe",
        stop_state: "Human Review",
        executable_labels: ["exec-ready"],
        blocked_labels: ["meta", "manual-env"]
      }
    )

    state = %Orchestrator.State{
      running: %{},
      claimed: MapSet.new(),
      codex_totals: %{input_tokens: 0, output_tokens: 0, total_tokens: 0, seconds_running: 0},
      retry_attempts: %{}
    }

    missing_exec_label_issue = %Issue{
      id: "issue-guardrails-dispatch-1",
      identifier: "MT-801",
      state: "Todo",
      title: "Missing exec label",
      description: "Should not dispatch",
      labels: ["improvement"]
    }

    blocked_issue = %Issue{
      id: "issue-guardrails-dispatch-2",
      identifier: "MT-802",
      state: "Todo",
      title: "Blocked by meta label",
      description: "Should not dispatch",
      labels: ["exec-ready", "meta"]
    }

    executable_issue = %Issue{
      id: "issue-guardrails-dispatch-3",
      identifier: "MT-803",
      state: "Todo",
      title: "Executable",
      description: "Should dispatch",
      labels: [" Exec-Ready "]
    }

    refute Orchestrator.should_dispatch_issue_for_test(missing_exec_label_issue, state)
    refute Orchestrator.should_dispatch_issue_for_test(blocked_issue, state)
    assert Orchestrator.should_dispatch_issue_for_test(executable_issue, state)
  end

  test "guardrails stop running issues when labels become non-executable during reconciliation" do
    issue_id = "issue-guardrails-reconcile"

    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_project_slug: "project",
      codex_command: "/bin/sh app-server",
      agent_guardrails: %{
        enabled: true,
        mode: "observe",
        stop_state: "Human Review",
        executable_labels: ["exec-ready"],
        blocked_labels: ["meta", "manual-env"]
      }
    )

    agent_pid =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    state = %Orchestrator.State{
      running: %{
        issue_id => %{
          pid: agent_pid,
          ref: nil,
          identifier: "MT-804",
          issue: %Issue{
            id: issue_id,
            identifier: "MT-804",
            state: "In Progress",
            labels: ["exec-ready"]
          },
          started_at: DateTime.utc_now()
        }
      },
      claimed: MapSet.new([issue_id]),
      codex_totals: %{input_tokens: 0, output_tokens: 0, total_tokens: 0, seconds_running: 0},
      retry_attempts: %{}
    }

    issue = %Issue{
      id: issue_id,
      identifier: "MT-804",
      state: "In Progress",
      title: "Guardrails reconciliation stop",
      description: "Worker should stop once labels become blocked",
      labels: ["exec-ready", "meta"]
    }

    updated_state = Orchestrator.reconcile_issue_states_for_test([issue], state)

    refute Map.has_key?(updated_state.running, issue_id)
    refute MapSet.member?(updated_state.claimed, issue_id)
    refute Process.alive?(agent_pid)
  end

  test "guardrails skip revalidation for retry dispatch when labels become non-executable" do
    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_project_slug: "project",
      codex_command: "/bin/sh app-server",
      agent_guardrails: %{
        enabled: true,
        mode: "observe",
        stop_state: "Human Review",
        executable_labels: ["exec-ready"],
        blocked_labels: ["meta", "manual-env"]
      }
    )

    stale_issue = %Issue{
      id: "issue-guardrails-retry",
      identifier: "MT-805",
      state: "Todo",
      title: "Retry candidate",
      description: "Initially executable",
      labels: ["exec-ready"]
    }

    refreshed_issue = %Issue{
      stale_issue
      | labels: ["exec-ready", "meta"]
    }

    assert {:skip, ^refreshed_issue} =
             Orchestrator.revalidate_issue_for_dispatch_for_test(stale_issue, fn [_issue_id] ->
               {:ok, [refreshed_issue]}
             end)
  end

  test "invalid guardrails config does not stop running issues during reconciliation" do
    issue_id = "issue-guardrails-invalid-reconcile"

    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_project_slug: "project",
      codex_command: "/bin/sh app-server",
      agent_guardrails: %{
        enabled: true,
        executable_labels: ["exec-ready"],
        blocked_labels: ["meta"]
      }
    )

    agent_pid =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    state = %Orchestrator.State{
      running: %{
        issue_id => %{
          pid: agent_pid,
          ref: nil,
          identifier: "MT-806",
          issue: %Issue{
            id: issue_id,
            identifier: "MT-806",
            state: "In Progress",
            labels: ["exec-ready"]
          },
          started_at: DateTime.utc_now()
        }
      },
      claimed: MapSet.new([issue_id]),
      codex_totals: %{input_tokens: 0, output_tokens: 0, total_tokens: 0, seconds_running: 0},
      retry_attempts: %{}
    }

    issue = %Issue{
      id: issue_id,
      identifier: "MT-806",
      state: "In Progress",
      title: "Invalid guardrails config",
      description: "Guardrails should not stop the worker while config is invalid",
      labels: ["exec-ready", "meta"]
    }

    updated_state = Orchestrator.reconcile_issue_states_for_test([issue], state)

    assert Map.has_key?(updated_state.running, issue_id)
    assert MapSet.member?(updated_state.claimed, issue_id)
    assert Process.alive?(agent_pid)
  end

  test "orchestrator request_continuation updates guardrail ledger and allows active issues" do
    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_project_slug: "project",
      codex_command: "/bin/sh app-server",
      agent_guardrails: %{
        enabled: true,
        mode: "observe",
        stop_state: "Human Review"
      }
    )

    orchestrator_name = Module.concat(__MODULE__, :ContinuationGateOrchestrator)
    {:ok, pid} = Orchestrator.start_link(name: orchestrator_name)

    on_exit(fn ->
      if Process.alive?(pid) do
        Process.exit(pid, :normal)
      end
    end)

    issue = %Issue{
      id: "issue-continuation-gate",
      identifier: "MT-807",
      title: "Continuation gate",
      description: "Ledger should update at turn boundaries",
      state: "In Progress",
      labels: ["exec-ready"]
    }

    running_entry = %{
      pid: self(),
      ref: make_ref(),
      identifier: issue.identifier,
      issue: issue,
      session_id: "thread-ledger",
      codex_input_tokens: 12,
      codex_output_tokens: 4,
      codex_total_tokens: 16,
      started_at: DateTime.utc_now()
    }

    initial_state = :sys.get_state(pid)

    :sys.replace_state(pid, fn _ ->
      %{
        initial_state
        | running: %{issue.id => running_entry},
          claimed: MapSet.new([issue.id])
      }
    end)

    assert {:allow, :probe, :fresh_summary, %Issue{id: "issue-continuation-gate"}} =
             Orchestrator.request_continuation_for_test(pid, issue.id, 1, fn [_issue_id] ->
               {:ok, [%{issue | state: "In Progress"}]}
             end)

    state = :sys.get_state(pid)
    ledger = Orchestrator.guardrail_ledger_for_test(state)[issue.id]

    assert ledger.issue_identifier == issue.identifier
    assert ledger.mode == :probe
    assert ledger.total_input_tokens == 12
    assert ledger.total_output_tokens == 4
    assert ledger.total_tokens == 16
    assert ledger.total_turns == 1
    assert ledger.continuation_runs == 0
    assert ledger.no_progress_turns == 0
    assert %DateTime{} = ledger.last_turn_completed_at
  end

  test "orchestrator request_continuation switches to fresh summary after soft budget hits" do
    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_project_slug: "project",
      codex_command: "/bin/sh app-server",
      agent_guardrails: %{
        enabled: true,
        mode: "observe",
        stop_state: "Human Review",
        probe: %{
          max_total_turns_per_issue: 2,
          soft_total_tokens: 10,
          hard_total_tokens: 50,
          soft_input_tokens: 20,
          hard_input_tokens: 40
        }
      }
    )

    orchestrator_name = Module.concat(__MODULE__, :ContinuationFreshSummaryOrchestrator)
    {:ok, pid} = Orchestrator.start_link(name: orchestrator_name)

    on_exit(fn ->
      if Process.alive?(pid) do
        Process.exit(pid, :normal)
      end
    end)

    issue = %Issue{
      id: "issue-fresh-summary",
      identifier: "MT-807-FRESH",
      title: "Fresh summary continuation",
      description: "Soft budget should switch continuation strategy",
      state: "In Progress",
      labels: ["exec-ready"]
    }

    running_entry = %{
      pid: self(),
      ref: make_ref(),
      identifier: issue.identifier,
      issue: issue,
      session_id: "thread-fresh-summary",
      codex_input_tokens: 8,
      codex_output_tokens: 4,
      codex_total_tokens: 12,
      started_at: DateTime.utc_now()
    }

    initial_state = :sys.get_state(pid)

    :sys.replace_state(pid, fn _ ->
      %{
        initial_state
        | running: %{issue.id => running_entry},
          claimed: MapSet.new([issue.id])
      }
    end)

    assert {:allow, :probe, :fresh_summary, %Issue{id: "issue-fresh-summary"}} =
             Orchestrator.request_continuation_for_test(pid, issue.id, 1, fn [_issue_id] ->
               {:ok, [%{issue | state: "In Progress"}]}
             end)
  end

  test "guardrail dispatch ledger increments continuation runs only for continuation retries" do
    started_at = DateTime.utc_now()

    issue = %Issue{
      id: "issue-ledger-dispatch",
      identifier: "MT-808",
      state: "Todo",
      title: "Ledger dispatch",
      description: "Track continuation runs"
    }

    state = %Orchestrator.State{}

    state =
      Orchestrator.put_guardrail_dispatch_for_test(state, issue, started_at, :initial)

    state =
      Orchestrator.put_guardrail_dispatch_for_test(state, issue, started_at, :failure)

    state =
      Orchestrator.put_guardrail_dispatch_for_test(state, issue, started_at, :continuation)

    ledger = Orchestrator.guardrail_ledger_for_test(state)[issue.id]

    assert ledger.continuation_runs == 1
    assert ledger.first_started_at == started_at
    assert ledger.last_turn_started_at == started_at
  end

  test "orchestrator request_continuation does not double-count the same turn number" do
    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_project_slug: "project",
      codex_command: "/bin/sh app-server",
      agent_guardrails: %{
        enabled: true,
        mode: "observe",
        stop_state: "Human Review"
      }
    )

    orchestrator_name = Module.concat(__MODULE__, :ContinuationDedupOrchestrator)
    {:ok, pid} = Orchestrator.start_link(name: orchestrator_name)

    on_exit(fn ->
      if Process.alive?(pid) do
        Process.exit(pid, :normal)
      end
    end)

    issue = %Issue{
      id: "issue-continuation-dedup",
      identifier: "MT-809",
      title: "Continuation dedup",
      description: "Same turn should not count twice",
      state: "In Progress"
    }

    running_entry = %{
      pid: self(),
      ref: make_ref(),
      identifier: issue.identifier,
      issue: issue,
      session_id: "thread-dedup",
      codex_input_tokens: 5,
      codex_output_tokens: 2,
      codex_total_tokens: 7,
      started_at: DateTime.utc_now()
    }

    initial_state = :sys.get_state(pid)

    :sys.replace_state(pid, fn _ ->
      %{
        initial_state
        | running: %{issue.id => running_entry},
          claimed: MapSet.new([issue.id])
      }
    end)

    for _ <- 1..2 do
      assert {:allow, :probe, :fresh_summary, %Issue{id: "issue-continuation-dedup"}} =
               Orchestrator.request_continuation_for_test(pid, issue.id, 1, fn [_issue_id] ->
                 {:ok, [%{issue | state: "In Progress"}]}
               end)
    end

    ledger = Orchestrator.guardrail_ledger_for_test(:sys.get_state(pid))[issue.id]
    assert ledger.total_turns == 1
  end

  test "workspace progress changes promote probe mode to default during continuation" do
    workspace_root =
      Path.join(
        System.tmp_dir!(),
        "workspace-progress-ledger-#{System.unique_integer([:positive])}"
      )

    orchestrator_name = Module.concat(__MODULE__, :WorkspaceProgressOrchestrator)

    try do
      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        tracker_project_slug: "project",
        codex_command: "/bin/sh app-server",
        agent_guardrails: %{
          enabled: true,
          mode: "observe",
          stop_state: "Human Review",
          default: %{no_progress_turn_limit: 1}
        }
      )

      workspace = Path.join(workspace_root, "MT-812")
      File.mkdir_p!(workspace)
      File.write!(Path.join(workspace, "tracked.txt"), "one\ntwo\n")
      System.cmd("git", ["-C", workspace, "init", "-b", "main"])
      System.cmd("git", ["-C", workspace, "config", "user.name", "Test User"])
      System.cmd("git", ["-C", workspace, "config", "user.email", "test@example.com"])
      System.cmd("git", ["-C", workspace, "add", "tracked.txt"])
      System.cmd("git", ["-C", workspace, "commit", "-m", "initial"])

      {:ok, pid} = Orchestrator.start_link(name: orchestrator_name)

      on_exit(fn ->
        if Process.alive?(pid) do
          Process.exit(pid, :normal)
        end
      end)

      issue = %Issue{
        id: "issue-progress-promotion",
        identifier: "MT-812",
        title: "Workspace progress",
        description: "Probe should promote after changed fingerprint",
        state: "In Progress"
      }

      running_entry = %{
        pid: self(),
        ref: make_ref(),
        identifier: issue.identifier,
        issue: issue,
        session_id: "thread-progress",
        codex_input_tokens: 1,
        codex_output_tokens: 1,
        codex_total_tokens: 2,
        started_at: DateTime.utc_now()
      }

      initial_state = :sys.get_state(pid)

      :sys.replace_state(pid, fn _ ->
        %{
          initial_state
          | running: %{issue.id => running_entry},
            claimed: MapSet.new([issue.id])
        }
      end)

      {:ok, baseline_fingerprint} = SymphonyElixir.WorkspaceProgress.capture(workspace)

      send(
        pid,
        {:codex_worker_update, issue.id,
         %{
           event: :workspace_ready,
           workspace: workspace,
           progress_fingerprint: baseline_fingerprint,
           timestamp: DateTime.utc_now()
         }}
      )

      assert {:allow, :probe, :fresh_summary, _} =
               Orchestrator.request_continuation_for_test(pid, issue.id, 1, fn [_issue_id] ->
                 {:ok, [%{issue | state: "In Progress"}]}
               end)

      ledger = Orchestrator.guardrail_ledger_for_test(:sys.get_state(pid))[issue.id]
      assert ledger.mode == :probe
      assert ledger.no_progress_turns == 0

      File.write!(Path.join(workspace, "tracked.txt"), "one\ntwo\nthree\n")

      assert {:allow, :default, :fresh_summary, _} =
               Orchestrator.request_continuation_for_test(pid, issue.id, 2, fn [_issue_id] ->
                 {:ok, [%{issue | state: "In Progress"}]}
               end)

      ledger = Orchestrator.guardrail_ledger_for_test(:sys.get_state(pid))[issue.id]
      assert ledger.mode == :default
      assert ledger.no_progress_turns == 0
    after
      File.rm_rf(workspace_root)
    end
  end

  test "first changed completed turn promotes probe mode from dispatch baseline" do
    workspace_root =
      Path.join(
        System.tmp_dir!(),
        "workspace-progress-first-turn-#{System.unique_integer([:positive])}"
      )

    orchestrator_name = Module.concat(__MODULE__, :WorkspaceFirstTurnOrchestrator)

    try do
      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        tracker_project_slug: "project",
        codex_command: "/bin/sh app-server",
        agent_guardrails: %{
          enabled: true,
          mode: "observe",
          stop_state: "Human Review",
          default: %{no_progress_turn_limit: 1}
        }
      )

      workspace = Path.join(workspace_root, "MT-813")
      File.mkdir_p!(workspace)
      File.write!(Path.join(workspace, "tracked.txt"), "one\ntwo\n")
      System.cmd("git", ["-C", workspace, "init", "-b", "main"])
      System.cmd("git", ["-C", workspace, "config", "user.name", "Test User"])
      System.cmd("git", ["-C", workspace, "config", "user.email", "test@example.com"])
      System.cmd("git", ["-C", workspace, "add", "tracked.txt"])
      System.cmd("git", ["-C", workspace, "commit", "-m", "initial"])

      {:ok, pid} = Orchestrator.start_link(name: orchestrator_name)

      on_exit(fn ->
        if Process.alive?(pid) do
          Process.exit(pid, :normal)
        end
      end)

      issue = %Issue{
        id: "issue-progress-first-turn",
        identifier: "MT-813",
        title: "Workspace progress first turn",
        description: "Probe should promote on the first changed turn",
        state: "In Progress"
      }

      initial_state = :sys.get_state(pid)
      started_at = DateTime.utc_now()

      _state =
        Orchestrator.put_guardrail_dispatch_for_test(initial_state, issue, started_at, :initial)

      running_entry = %{
        pid: self(),
        ref: make_ref(),
        identifier: issue.identifier,
        issue: issue,
        session_id: "thread-progress-first",
        workspace: workspace,
        codex_input_tokens: 1,
        codex_output_tokens: 1,
        codex_total_tokens: 2,
        started_at: started_at
      }

      :sys.replace_state(pid, fn _ ->
        %{
          initial_state
          | running: %{issue.id => running_entry},
            claimed: MapSet.new([issue.id])
        }
      end)

      {:ok, baseline_fingerprint} = SymphonyElixir.WorkspaceProgress.capture(workspace)

      send(
        pid,
        {:codex_worker_update, issue.id,
         %{
           event: :workspace_ready,
           workspace: workspace,
           progress_fingerprint: baseline_fingerprint,
           timestamp: DateTime.utc_now()
         }}
      )

      File.write!(Path.join(workspace, "tracked.txt"), "one\ntwo\nthree\n")

      assert {:allow, :default, :reuse_thread, _} =
               Orchestrator.request_continuation_for_test(pid, issue.id, 1, fn [_issue_id] ->
                 {:ok, [%{issue | state: "In Progress"}]}
               end)

      ledger = Orchestrator.guardrail_ledger_for_test(:sys.get_state(pid))[issue.id]
      assert ledger.mode == :default
      assert ledger.no_progress_turns == 0
    after
      File.rm_rf(workspace_root)
    end
  end

  test "tracker refresh failure still records workspace progress for the completed turn" do
    workspace_root =
      Path.join(
        System.tmp_dir!(),
        "workspace-progress-refresh-failure-#{System.unique_integer([:positive])}"
      )

    orchestrator_name = Module.concat(__MODULE__, :WorkspaceRefreshFailureOrchestrator)

    try do
      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        tracker_project_slug: "project",
        codex_command: "/bin/sh app-server",
        agent_guardrails: %{
          enabled: true,
          mode: "observe",
          stop_state: "Human Review"
        }
      )

      workspace = Path.join(workspace_root, "MT-814")
      File.mkdir_p!(workspace)
      File.write!(Path.join(workspace, "tracked.txt"), "one\ntwo\n")
      System.cmd("git", ["-C", workspace, "init", "-b", "main"])
      System.cmd("git", ["-C", workspace, "config", "user.name", "Test User"])
      System.cmd("git", ["-C", workspace, "config", "user.email", "test@example.com"])
      System.cmd("git", ["-C", workspace, "add", "tracked.txt"])
      System.cmd("git", ["-C", workspace, "commit", "-m", "initial"])

      {:ok, pid} = Orchestrator.start_link(name: orchestrator_name)

      on_exit(fn ->
        if Process.alive?(pid) do
          Process.exit(pid, :normal)
        end
      end)

      issue = %Issue{
        id: "issue-progress-refresh-failure",
        identifier: "MT-814",
        title: "Workspace progress refresh failure",
        description: "Fingerprint should still be recorded",
        state: "In Progress"
      }

      initial_state = :sys.get_state(pid)
      started_at = DateTime.utc_now()
      _state = Orchestrator.put_guardrail_dispatch_for_test(initial_state, issue, started_at, :initial)

      running_entry = %{
        pid: self(),
        ref: make_ref(),
        identifier: issue.identifier,
        issue: issue,
        session_id: "thread-progress-failure",
        workspace: workspace,
        codex_input_tokens: 1,
        codex_output_tokens: 1,
        codex_total_tokens: 2,
        started_at: started_at
      }

      :sys.replace_state(pid, fn _ ->
        %{
          initial_state
          | running: %{issue.id => running_entry},
            claimed: MapSet.new([issue.id])
        }
      end)

      {:ok, baseline_fingerprint} = SymphonyElixir.WorkspaceProgress.capture(workspace)

      send(
        pid,
        {:codex_worker_update, issue.id,
         %{
           event: :workspace_ready,
           workspace: workspace,
           progress_fingerprint: baseline_fingerprint,
           timestamp: DateTime.utc_now()
         }}
      )

      File.write!(Path.join(workspace, "tracked.txt"), "one\ntwo\nthree\n")

      assert {:deny, {:issue_state_refresh_failed, :boom}} =
               Orchestrator.request_continuation_for_test(pid, issue.id, 1, fn [_issue_id] ->
                 {:error, :boom}
               end)

      ledger = Orchestrator.guardrail_ledger_for_test(:sys.get_state(pid))[issue.id]
      refute is_nil(ledger.last_progress_fingerprint)
      assert ledger.total_turns == 1
    after
      File.rm_rf(workspace_root)
    end
  end

  test "continuation redispatch preserves the previous completed-turn progress baseline" do
    fingerprint = %{
      kind: :git,
      changed_file_count: 1,
      added_lines: 2,
      removed_lines: 0,
      changed_files_hash: String.duplicate("c", 64)
    }

    issue = %Issue{
      id: "issue-progress-redispatch",
      identifier: "MT-815",
      state: "In Progress",
      title: "Progress redispatch",
      description: "Progress baseline should survive continuation redispatch"
    }

    started_at = DateTime.utc_now()

    state = %Orchestrator.State{
      guardrail_ledger: %{
        issue.id => %{
          issue_identifier: issue.identifier,
          mode: :default,
          stop_reason: nil,
          total_input_tokens: 0,
          total_output_tokens: 0,
          total_tokens: 0,
          total_turns: 1,
          continuation_runs: 0,
          no_progress_turns: 0,
          first_started_at: started_at,
          last_turn_started_at: started_at,
          last_turn_completed_at: started_at,
          last_progress_fingerprint: fingerprint,
          last_warning_at: nil,
          progress_baseline_pending: false,
          last_completed_turn_number: 1,
          last_continuation_decision: nil
        }
      }
    }

    state = Orchestrator.put_guardrail_dispatch_for_test(state, issue, started_at, :continuation)
    ledger = Orchestrator.guardrail_ledger_for_test(state)[issue.id]

    assert ledger.last_progress_fingerprint == fingerprint
    refute ledger.progress_baseline_pending
    assert ledger.continuation_runs == 1
  end

  test "normal worker exit does not schedule continuation retry after gate denial" do
    issue_id = "issue-denied-continuation"
    ref = make_ref()
    orchestrator_name = Module.concat(__MODULE__, :DeniedContinuationOrchestrator)
    {:ok, pid} = Orchestrator.start_link(name: orchestrator_name)

    on_exit(fn ->
      if Process.alive?(pid) do
        Process.exit(pid, :normal)
      end
    end)

    initial_state = :sys.get_state(pid)

    running_entry = %{
      pid: self(),
      ref: ref,
      identifier: "MT-810",
      issue: %Issue{id: issue_id, identifier: "MT-810", state: "In Progress"},
      started_at: DateTime.utc_now()
    }

    guardrail_ledger = %{
      issue_id => %{
        issue_identifier: "MT-810",
        mode: :probe,
        stop_reason: :issue_not_active,
        total_input_tokens: 0,
        total_output_tokens: 0,
        total_tokens: 0,
        total_turns: 1,
        continuation_runs: 0,
        no_progress_turns: 0,
        first_started_at: DateTime.utc_now(),
        last_turn_started_at: DateTime.utc_now(),
        last_turn_completed_at: DateTime.utc_now(),
        last_progress_fingerprint: nil,
        last_warning_at: nil,
        last_completed_turn_number: 1,
        last_continuation_decision: {:deny, :issue_not_active}
      }
    }

    :sys.replace_state(pid, fn _ ->
      %{
        initial_state
        | running: %{issue_id => running_entry},
          claimed: MapSet.new([issue_id]),
          retry_attempts: %{},
          guardrail_ledger: guardrail_ledger
      }
    end)

    send(pid, {:DOWN, ref, :process, self(), :normal})
    Process.sleep(50)
    state = :sys.get_state(pid)

    refute Map.has_key?(state.retry_attempts, issue_id)
    refute MapSet.member?(state.claimed, issue_id)
  end

  test "retryable gate denial schedules a failure retry instead of continuation retry" do
    issue_id = "issue-denied-refresh"
    ref = make_ref()
    orchestrator_name = Module.concat(__MODULE__, :DeniedRefreshRetryOrchestrator)
    {:ok, pid} = Orchestrator.start_link(name: orchestrator_name)

    on_exit(fn ->
      if Process.alive?(pid) do
        Process.exit(pid, :normal)
      end
    end)

    initial_state = :sys.get_state(pid)

    running_entry = %{
      pid: self(),
      ref: ref,
      identifier: "MT-811",
      issue: %Issue{id: issue_id, identifier: "MT-811", state: "In Progress"},
      started_at: DateTime.utc_now()
    }

    guardrail_ledger = %{
      issue_id => %{
        issue_identifier: "MT-811",
        mode: :probe,
        stop_reason: {:issue_state_refresh_failed, :boom},
        total_input_tokens: 0,
        total_output_tokens: 0,
        total_tokens: 0,
        total_turns: 1,
        continuation_runs: 0,
        no_progress_turns: 0,
        first_started_at: DateTime.utc_now(),
        last_turn_started_at: DateTime.utc_now(),
        last_turn_completed_at: DateTime.utc_now(),
        last_progress_fingerprint: nil,
        last_warning_at: nil,
        last_completed_turn_number: 1,
        last_continuation_decision: {:deny, {:issue_state_refresh_failed, :boom}}
      }
    }

    :sys.replace_state(pid, fn _ ->
      %{
        initial_state
        | running: %{issue_id => running_entry},
          claimed: MapSet.new([issue_id]),
          retry_attempts: %{},
          guardrail_ledger: guardrail_ledger
      }
    end)

    send(pid, {:DOWN, ref, :process, self(), :normal})
    Process.sleep(50)
    state = :sys.get_state(pid)

    assert %{attempt: 1, error: error, retry_kind: :failure} = state.retry_attempts[issue_id]
    assert error =~ "continuation denied"
  end

  test "observe mode records hard token hits without stopping the worker" do
    workspace_root = Path.join(System.tmp_dir!(), "guardrail-observe-#{System.unique_integer([:positive])}")

    try do
      write_workflow_file!(Workflow.workflow_file_path(),
        tracker_kind: "memory",
        workspace_root: workspace_root,
        agent_guardrails: %{
          enabled: true,
          mode: "observe",
          stop_state: "Human Review",
          probe: %{
            hard_total_tokens: 10,
            hard_input_tokens: 10,
            max_total_turns_per_issue: 2,
            soft_total_tokens: 5,
            soft_input_tokens: 5
          }
        }
      )

      issue_id = "issue-observe-hard-limit"
      orchestrator_name = Module.concat(__MODULE__, :ObserveHardLimitOrchestrator)
      {:ok, pid} = Orchestrator.start_link(name: orchestrator_name)

      on_exit(fn ->
        if Process.alive?(pid) do
          Process.exit(pid, :normal)
        end
      end)

      worker_pid =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      initial_state = :sys.get_state(pid)
      ref = Process.monitor(worker_pid)

      running_entry = %{
        pid: worker_pid,
        ref: ref,
        identifier: "MT-816",
        issue: %Issue{id: issue_id, identifier: "MT-816", state: "In Progress"},
        session_id: "thread-observe",
        codex_input_tokens: 0,
        codex_output_tokens: 0,
        codex_total_tokens: 0,
        codex_last_reported_input_tokens: 0,
        codex_last_reported_output_tokens: 0,
        codex_last_reported_total_tokens: 0,
        started_at: DateTime.utc_now()
      }

      :sys.replace_state(pid, fn _ ->
        %{initial_state | running: %{issue_id => running_entry}, claimed: MapSet.new([issue_id])}
      end)

      send(
        pid,
        {:codex_worker_update, issue_id,
         %{
           event: :notification,
           payload: %{
             "method" => "thread/tokenUsage/updated",
             "params" => %{
               "tokenUsage" => %{
                 "total" => %{"input_tokens" => 12, "output_tokens" => 1, "total_tokens" => 13}
               }
             }
           },
           timestamp: DateTime.utc_now()
         }}
      )

      Process.sleep(50)
      state = :sys.get_state(pid)
      first_warning_at = get_in(Orchestrator.guardrail_ledger_for_test(state), [issue_id, :last_warning_at])

      send(
        pid,
        {:codex_worker_update, issue_id,
         %{
           event: :notification,
           payload: %{
             "method" => "thread/tokenUsage/updated",
             "params" => %{
               "tokenUsage" => %{
                 "total" => %{"input_tokens" => 12, "output_tokens" => 1, "total_tokens" => 13}
               }
             }
           },
           timestamp: DateTime.utc_now()
         }}
      )

      Process.sleep(50)
      state = :sys.get_state(pid)
      assert Process.alive?(worker_pid)
      assert Orchestrator.guardrail_holds_for_test(state) == %{}

      assert get_in(Orchestrator.guardrail_ledger_for_test(state), [issue_id, :last_guardrail_reason]) ==
               :hard_total_token_limit

      assert get_in(Orchestrator.guardrail_ledger_for_test(state), [issue_id, :last_warning_at]) ==
               first_warning_at
    after
      File.rm_rf(workspace_root)
    end
  end

  test "enforce mode stops the worker persists the hold and suppresses retry" do
    workspace_root =
      Path.join(System.tmp_dir!(), "guardrail-stop-#{System.unique_integer([:positive])}")

    try do
      Application.put_env(:symphony_elixir, :memory_tracker_recipient, self())

      write_workflow_file!(Workflow.workflow_file_path(),
        tracker_kind: "memory",
        workspace_root: workspace_root,
        agent_guardrails: %{
          enabled: true,
          mode: "enforce",
          stop_state: "Human Review",
          probe: %{
            hard_total_tokens: 10,
            hard_input_tokens: 10,
            max_total_turns_per_issue: 2,
            soft_total_tokens: 5,
            soft_input_tokens: 5
          }
        }
      )

      issue_id = "issue-enforce-hard-limit"
      identifier = "MT-817"
      workspace = Path.join(workspace_root, identifier)
      File.mkdir_p!(workspace)

      orchestrator_name = Module.concat(__MODULE__, :EnforceHardLimitOrchestrator)
      {:ok, pid} = Orchestrator.start_link(name: orchestrator_name)

      on_exit(fn ->
        if Process.alive?(pid) do
          Process.exit(pid, :normal)
        end
      end)

      worker_pid =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      initial_state = :sys.get_state(pid)
      ref = Process.monitor(worker_pid)

      running_entry = %{
        pid: worker_pid,
        ref: ref,
        identifier: identifier,
        issue: %Issue{id: issue_id, identifier: identifier, state: "In Progress"},
        workspace: workspace,
        session_id: "thread-enforce",
        codex_input_tokens: 0,
        codex_output_tokens: 0,
        codex_total_tokens: 0,
        codex_last_reported_input_tokens: 0,
        codex_last_reported_output_tokens: 0,
        codex_last_reported_total_tokens: 0,
        started_at: DateTime.utc_now()
      }

      :sys.replace_state(pid, fn _ ->
        %{initial_state | running: %{issue_id => running_entry}, claimed: MapSet.new([issue_id])}
      end)

      send(
        pid,
        {:codex_worker_update, issue_id,
         %{
           event: :notification,
           payload: %{
             "method" => "thread/tokenUsage/updated",
             "params" => %{
               "tokenUsage" => %{
                 "total" => %{"input_tokens" => 12, "output_tokens" => 1, "total_tokens" => 13}
               }
             }
           },
           timestamp: DateTime.utc_now()
         }}
      )

      send(
        pid,
        {:codex_worker_update, issue_id,
         %{
           event: :notification,
           payload: %{
             "method" => "thread/tokenUsage/updated",
             "params" => %{
               "tokenUsage" => %{
                 "total" => %{"input_tokens" => 12, "output_tokens" => 1, "total_tokens" => 13}
               }
             }
           },
           timestamp: DateTime.utc_now()
         }}
      )

      assert_receive {:memory_tracker_comment, ^issue_id, body}, 1_000
      assert body =~ "hard_total_token_limit"
      refute_receive {:memory_tracker_comment, ^issue_id, _}, 200
      assert_receive {:memory_tracker_state_update, ^issue_id, "Human Review"}, 1_000
      refute_receive {:memory_tracker_state_update, ^issue_id, "Human Review"}, 200

      Process.sleep(100)
      state = :sys.get_state(pid)

      refute Process.alive?(worker_pid)
      refute Map.has_key?(state.retry_attempts, issue_id)
      assert Map.has_key?(Orchestrator.guardrail_holds_for_test(state), issue_id)
      assert File.exists?(Path.join([workspace, "shared", "guardrail_state.json"]))
    after
      File.rm_rf(workspace_root)
    end
  end

  test "continuation ceiling in enforce mode holds the issue instead of scheduling continuation retry" do
    workspace_root =
      Path.join(System.tmp_dir!(), "guardrail-continuation-#{System.unique_integer([:positive])}")

    try do
      Application.put_env(:symphony_elixir, :memory_tracker_recipient, self())

      write_workflow_file!(Workflow.workflow_file_path(),
        tracker_kind: "memory",
        workspace_root: workspace_root,
        agent_guardrails: %{
          enabled: true,
          mode: "enforce",
          stop_state: "Human Review",
          default: %{
            max_total_turns_per_issue: 3,
            max_continuation_runs_per_issue: 1,
            no_progress_turn_limit: 1,
            soft_total_tokens: 100,
            hard_total_tokens: 200,
            soft_input_tokens: 100,
            hard_input_tokens: 200
          }
        }
      )

      issue_id = "issue-continuation-ceiling"
      ref = make_ref()
      orchestrator_name = Module.concat(__MODULE__, :ContinuationCeilingOrchestrator)
      {:ok, pid} = Orchestrator.start_link(name: orchestrator_name)

      on_exit(fn ->
        if Process.alive?(pid) do
          Process.exit(pid, :normal)
        end
      end)

      initial_state = :sys.get_state(pid)

      running_entry = %{
        pid: self(),
        ref: ref,
        identifier: "MT-818",
        issue: %Issue{id: issue_id, identifier: "MT-818", state: "In Progress"},
        started_at: DateTime.utc_now()
      }

      guardrail_ledger = %{
        issue_id => %{
          issue_identifier: "MT-818",
          mode: :default,
          stop_reason: nil,
          total_input_tokens: 0,
          total_output_tokens: 0,
          total_tokens: 0,
          total_turns: 2,
          continuation_runs: 1,
          no_progress_turns: 0,
          first_started_at: DateTime.utc_now(),
          last_turn_started_at: DateTime.utc_now(),
          last_turn_completed_at: DateTime.utc_now(),
          last_progress_fingerprint: nil,
          last_warning_at: nil,
          progress_baseline_pending: false,
          last_completed_turn_number: 2,
          last_continuation_decision: nil
        }
      }

      :sys.replace_state(pid, fn _ ->
        %{
          initial_state
          | running: %{issue_id => running_entry},
            claimed: MapSet.new([issue_id]),
            retry_attempts: %{},
            guardrail_ledger: guardrail_ledger
        }
      end)

      send(pid, {:DOWN, ref, :process, self(), :normal})
      assert_receive {:memory_tracker_state_update, ^issue_id, "Human Review"}, 1_000
      Process.sleep(50)
      state = :sys.get_state(pid)

      refute Map.has_key?(state.retry_attempts, issue_id)
      assert Map.has_key?(Orchestrator.guardrail_holds_for_test(state), issue_id)
    after
      File.rm_rf(workspace_root)
    end
  end

  test "turn-boundary total-turn ceiling in enforce mode denies continuation and creates a hold" do
    workspace_root = Path.join(System.tmp_dir!(), "guardrail-total-turns-#{System.unique_integer([:positive])}")

    try do
      Application.put_env(:symphony_elixir, :memory_tracker_recipient, self())

      write_workflow_file!(Workflow.workflow_file_path(),
        tracker_kind: "memory",
        workspace_root: workspace_root,
        agent_guardrails: %{
          enabled: true,
          mode: "enforce",
          stop_state: "Human Review",
          probe: %{
            max_total_turns_per_issue: 1,
            hard_total_tokens: 100,
            hard_input_tokens: 100,
            soft_total_tokens: 50,
            soft_input_tokens: 50
          }
        }
      )

      orchestrator_name = Module.concat(__MODULE__, :TotalTurnGuardrailOrchestrator)
      {:ok, pid} = Orchestrator.start_link(name: orchestrator_name)

      on_exit(fn ->
        if Process.alive?(pid) do
          Process.exit(pid, :normal)
        end
      end)

      issue = %Issue{
        id: "issue-total-turn-limit",
        identifier: "MT-821",
        title: "Total turn ceiling",
        description: "Turn-boundary ceiling should hold the issue",
        state: "In Progress"
      }

      running_entry = %{
        pid: self(),
        ref: make_ref(),
        identifier: issue.identifier,
        issue: issue,
        session_id: "thread-total-turn",
        codex_input_tokens: 0,
        codex_output_tokens: 0,
        codex_total_tokens: 0,
        started_at: DateTime.utc_now()
      }

      initial_state = :sys.get_state(pid)

      :sys.replace_state(pid, fn _ ->
        %{initial_state | running: %{issue.id => running_entry}, claimed: MapSet.new([issue.id])}
      end)

      assert {:deny, :max_total_turns_per_issue} =
               Orchestrator.request_continuation_for_test(pid, issue.id, 1, fn [_issue_id] ->
                 {:ok, [%{issue | state: "In Progress"}]}
               end)

      assert_receive {:memory_tracker_state_update, "issue-total-turn-limit", "Human Review"}, 1_000
      state = :sys.get_state(pid)
      assert Map.has_key?(Orchestrator.guardrail_holds_for_test(state), issue.id)
    after
      File.rm_rf(workspace_root)
    end
  end

  test "turn-boundary does not stop an issue that is already non-active after refresh" do
    workspace_root =
      Path.join(System.tmp_dir!(), "guardrail-non-active-#{System.unique_integer([:positive])}")

    try do
      Application.put_env(:symphony_elixir, :memory_tracker_recipient, self())

      write_workflow_file!(Workflow.workflow_file_path(),
        tracker_kind: "memory",
        workspace_root: workspace_root,
        agent_guardrails: %{
          enabled: true,
          mode: "enforce",
          stop_state: "Human Review",
          probe: %{
            max_total_turns_per_issue: 1,
            hard_total_tokens: 100,
            hard_input_tokens: 100,
            soft_total_tokens: 50,
            soft_input_tokens: 50
          }
        }
      )

      orchestrator_name = Module.concat(__MODULE__, :TotalTurnNonActiveOrchestrator)
      {:ok, pid} = Orchestrator.start_link(name: orchestrator_name)

      on_exit(fn ->
        if Process.alive?(pid) do
          Process.exit(pid, :normal)
        end
      end)

      issue = %Issue{
        id: "issue-total-turn-done",
        identifier: "MT-821-DONE",
        title: "Total turn ceiling but already done",
        description: "Done issues should not be moved back to Human Review",
        state: "In Progress"
      }

      running_entry = %{
        pid: self(),
        ref: make_ref(),
        identifier: issue.identifier,
        issue: issue,
        session_id: "thread-total-turn-done",
        codex_input_tokens: 0,
        codex_output_tokens: 0,
        codex_total_tokens: 0,
        started_at: DateTime.utc_now()
      }

      initial_state = :sys.get_state(pid)

      :sys.replace_state(pid, fn _ ->
        %{initial_state | running: %{issue.id => running_entry}, claimed: MapSet.new([issue.id])}
      end)

      assert {:deny, :issue_not_active} =
               Orchestrator.request_continuation_for_test(pid, issue.id, 1, fn [_issue_id] ->
                 {:ok, [%{issue | state: "Done"}]}
               end)

      refute_receive {:memory_tracker_comment, "issue-total-turn-done", _}, 200
      refute_receive {:memory_tracker_state_update, "issue-total-turn-done", _}, 200

      state = :sys.get_state(pid)
      refute Map.has_key?(Orchestrator.guardrail_holds_for_test(state), issue.id)
    after
      File.rm_rf(workspace_root)
    end
  end

  test "turn-boundary no-progress ceiling in observe mode records the hit but still allows continuation" do
    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "memory",
      agent_guardrails: %{
        enabled: true,
        mode: "observe",
        stop_state: "Human Review",
        default: %{
          max_total_turns_per_issue: 5,
          max_continuation_runs_per_issue: 5,
          no_progress_turn_limit: 1,
          soft_total_tokens: 100,
          hard_total_tokens: 200,
          soft_input_tokens: 100,
          hard_input_tokens: 200
        }
      }
    )

    orchestrator_name = Module.concat(__MODULE__, :NoProgressObserveOrchestrator)
    {:ok, pid} = Orchestrator.start_link(name: orchestrator_name)

    on_exit(fn ->
      if Process.alive?(pid) do
        Process.exit(pid, :normal)
      end
    end)

    issue = %Issue{
      id: "issue-no-progress-observe",
      identifier: "MT-822",
      title: "No progress observe",
      description: "Observe mode should not stop the issue",
      state: "In Progress"
    }

    running_entry = %{
      pid: self(),
      ref: make_ref(),
      identifier: issue.identifier,
      issue: issue,
      session_id: "thread-no-progress",
      codex_input_tokens: 0,
      codex_output_tokens: 0,
      codex_total_tokens: 0,
      started_at: DateTime.utc_now()
    }

    ledger = %{
      issue.id => %{
        issue_identifier: issue.identifier,
        mode: :default,
        stop_reason: nil,
        total_input_tokens: 0,
        total_output_tokens: 0,
        total_tokens: 0,
        total_turns: 1,
        continuation_runs: 0,
        no_progress_turns: 1,
        first_started_at: DateTime.utc_now(),
        last_turn_started_at: DateTime.utc_now(),
        last_turn_completed_at: DateTime.utc_now(),
        last_progress_fingerprint: nil,
        last_warning_at: nil,
        progress_baseline_pending: false,
        last_completed_turn_number: 1,
        last_continuation_decision: nil
      }
    }

    initial_state = :sys.get_state(pid)

    :sys.replace_state(pid, fn _ ->
      %{initial_state | running: %{issue.id => running_entry}, claimed: MapSet.new([issue.id]), guardrail_ledger: ledger}
    end)

    assert {:allow, :default, :fresh_summary, _} =
             Orchestrator.request_continuation_for_test(pid, issue.id, 2, fn [_issue_id] ->
               {:ok, [%{issue | state: "In Progress"}]}
             end)

    state = :sys.get_state(pid)
    refute Map.has_key?(Orchestrator.guardrail_holds_for_test(state), issue.id)

    assert get_in(Orchestrator.guardrail_ledger_for_test(state), [issue.id, :last_guardrail_reason]) ==
             :no_progress_turn_limit
  end

  test "startup reloads persisted guardrail holds" do
    workspace_root = Path.join(System.tmp_dir!(), "guardrail-reload-#{System.unique_integer([:positive])}")

    try do
      hold_dir = Path.join([workspace_root, "MT-819", "shared"])
      File.mkdir_p!(hold_dir)

      File.write!(
        Path.join(hold_dir, "guardrail_state.json"),
        Jason.encode!(%{
          "issue_id" => "issue-reloaded-hold",
          "identifier" => "MT-819",
          "stop_reason" => "hard_total_token_limit",
          "held_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
          "input_tokens" => 99,
          "total_tokens" => 100,
          "writeback" => %{"comment" => "ok", "state" => "failed"}
        })
      )

      write_workflow_file!(Workflow.workflow_file_path(),
        tracker_kind: "memory",
        workspace_root: workspace_root
      )

      orchestrator_name = Module.concat(__MODULE__, :ReloadedGuardrailHoldOrchestrator)
      {:ok, pid} = Orchestrator.start_link(name: orchestrator_name)

      on_exit(fn ->
        if Process.alive?(pid) do
          Process.exit(pid, :normal)
        end
      end)

      state = :sys.get_state(pid)
      hold = Orchestrator.guardrail_holds_for_test(state)["issue-reloaded-hold"]

      assert hold.identifier == "MT-819"
      assert hold.stop_reason == "hard_total_token_limit"
      assert hold.total_tokens == 100
    after
      File.rm_rf(workspace_root)
    end
  end

  test "startup ignores continuation artifacts in shared guardrail state" do
    workspace_root =
      Path.join(System.tmp_dir!(), "guardrail-artifact-reload-#{System.unique_integer([:positive])}")

    try do
      hold_dir = Path.join([workspace_root, "MT-820", "shared"])
      File.mkdir_p!(hold_dir)

      File.write!(
        Path.join(hold_dir, "guardrail_state.json"),
        Jason.encode!(%{
          "kind" => "continuation_artifact",
          "issue_id" => "issue-continuation-artifact",
          "identifier" => "MT-820",
          "prompt_mode" => "continuation_summary",
          "turn_number" => 2,
          "max_turns" => 3,
          "context_summary_path" => "shared/context_summary.md"
        })
      )

      write_workflow_file!(Workflow.workflow_file_path(),
        tracker_kind: "memory",
        workspace_root: workspace_root
      )

      orchestrator_name = Module.concat(__MODULE__, :ContinuationArtifactReloadOrchestrator)
      {:ok, pid} = Orchestrator.start_link(name: orchestrator_name)

      on_exit(fn ->
        if Process.alive?(pid) do
          Process.exit(pid, :normal)
        end
      end)

      state = :sys.get_state(pid)
      assert Orchestrator.guardrail_holds_for_test(state) == %{}
    after
      File.rm_rf(workspace_root)
    end
  end

  test "state writeback failure still leaves the issue held" do
    workspace_root = Path.join(System.tmp_dir!(), "guardrail-writeback-#{System.unique_integer([:positive])}")

    try do
      Application.put_env(:symphony_elixir, :memory_tracker_recipient, self())
      Application.put_env(:symphony_elixir, :memory_tracker_state_update_result, {:error, :boom})

      write_workflow_file!(Workflow.workflow_file_path(),
        tracker_kind: "memory",
        workspace_root: workspace_root,
        agent_guardrails: %{
          enabled: true,
          mode: "enforce",
          stop_state: "Human Review",
          probe: %{
            hard_total_tokens: 10,
            hard_input_tokens: 10,
            max_total_turns_per_issue: 2,
            soft_total_tokens: 5,
            soft_input_tokens: 5
          }
        }
      )

      issue_id = "issue-writeback-failure"
      identifier = "MT-820"
      workspace = Path.join(workspace_root, identifier)
      File.mkdir_p!(workspace)

      orchestrator_name = Module.concat(__MODULE__, :WritebackFailureOrchestrator)
      {:ok, pid} = Orchestrator.start_link(name: orchestrator_name)

      on_exit(fn ->
        if Process.alive?(pid) do
          Process.exit(pid, :normal)
        end
      end)

      worker_pid =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      initial_state = :sys.get_state(pid)
      ref = Process.monitor(worker_pid)

      running_entry = %{
        pid: worker_pid,
        ref: ref,
        identifier: identifier,
        issue: %Issue{id: issue_id, identifier: identifier, state: "In Progress"},
        workspace: workspace,
        session_id: "thread-writeback",
        codex_input_tokens: 0,
        codex_output_tokens: 0,
        codex_total_tokens: 0,
        codex_last_reported_input_tokens: 0,
        codex_last_reported_output_tokens: 0,
        codex_last_reported_total_tokens: 0,
        started_at: DateTime.utc_now()
      }

      :sys.replace_state(pid, fn _ ->
        %{initial_state | running: %{issue_id => running_entry}, claimed: MapSet.new([issue_id])}
      end)

      send(
        pid,
        {:codex_worker_update, issue_id,
         %{
           event: :notification,
           payload: %{
             "method" => "thread/tokenUsage/updated",
             "params" => %{
               "tokenUsage" => %{
                 "total" => %{"input_tokens" => 12, "output_tokens" => 1, "total_tokens" => 13}
               }
             }
           },
           timestamp: DateTime.utc_now()
         }}
      )

      assert_receive {:memory_tracker_comment, ^issue_id, _body}, 1_000
      Process.sleep(100)
      state = :sys.get_state(pid)
      hold = Orchestrator.guardrail_holds_for_test(state)[issue_id]

      assert hold.writeback["state"] =~ "failed"
      assert File.exists?(Path.join([workspace, "shared", "guardrail_state.json"]))
    after
      File.rm_rf(workspace_root)
    end
  end

  test "normal worker exit schedules active-state continuation retry" do
    issue_id = "issue-resume"
    ref = make_ref()
    orchestrator_name = Module.concat(__MODULE__, :ContinuationOrchestrator)
    {:ok, pid} = Orchestrator.start_link(name: orchestrator_name)

    on_exit(fn ->
      if Process.alive?(pid) do
        Process.exit(pid, :normal)
      end
    end)

    initial_state = :sys.get_state(pid)

    running_entry = %{
      pid: self(),
      ref: ref,
      identifier: "MT-558",
      issue: %Issue{id: issue_id, identifier: "MT-558", state: "In Progress"},
      started_at: DateTime.utc_now()
    }

    :sys.replace_state(pid, fn _ ->
      initial_state
      |> Map.put(:running, %{issue_id => running_entry})
      |> Map.put(:claimed, MapSet.new([issue_id]))
      |> Map.put(:retry_attempts, %{})
    end)

    send(pid, {:DOWN, ref, :process, self(), :normal})
    Process.sleep(50)
    state = :sys.get_state(pid)

    refute Map.has_key?(state.running, issue_id)
    assert MapSet.member?(state.completed, issue_id)
    assert %{attempt: 1, due_at_ms: due_at_ms} = state.retry_attempts[issue_id]
    assert is_integer(due_at_ms)
    assert_due_in_range(due_at_ms, 500, 1_100)
  end

  test "abnormal worker exit increments retry attempt progressively" do
    issue_id = "issue-crash"
    ref = make_ref()
    orchestrator_name = Module.concat(__MODULE__, :CrashRetryOrchestrator)
    {:ok, pid} = Orchestrator.start_link(name: orchestrator_name)

    on_exit(fn ->
      if Process.alive?(pid) do
        Process.exit(pid, :normal)
      end
    end)

    initial_state = :sys.get_state(pid)

    running_entry = %{
      pid: self(),
      ref: ref,
      identifier: "MT-559",
      retry_attempt: 2,
      issue: %Issue{id: issue_id, identifier: "MT-559", state: "In Progress"},
      started_at: DateTime.utc_now()
    }

    :sys.replace_state(pid, fn _ ->
      initial_state
      |> Map.put(:running, %{issue_id => running_entry})
      |> Map.put(:claimed, MapSet.new([issue_id]))
      |> Map.put(:retry_attempts, %{})
    end)

    send(pid, {:DOWN, ref, :process, self(), :boom})
    Process.sleep(50)
    state = :sys.get_state(pid)

    assert %{attempt: 3, due_at_ms: due_at_ms, identifier: "MT-559", error: "agent exited: :boom"} =
             state.retry_attempts[issue_id]

    assert_due_in_range(due_at_ms, 39_500, 40_500)
  end

  test "first abnormal worker exit waits before retrying" do
    issue_id = "issue-crash-initial"
    ref = make_ref()
    orchestrator_name = Module.concat(__MODULE__, :InitialCrashRetryOrchestrator)
    {:ok, pid} = Orchestrator.start_link(name: orchestrator_name)

    on_exit(fn ->
      if Process.alive?(pid) do
        Process.exit(pid, :normal)
      end
    end)

    initial_state = :sys.get_state(pid)

    running_entry = %{
      pid: self(),
      ref: ref,
      identifier: "MT-560",
      issue: %Issue{id: issue_id, identifier: "MT-560", state: "In Progress"},
      started_at: DateTime.utc_now()
    }

    :sys.replace_state(pid, fn _ ->
      initial_state
      |> Map.put(:running, %{issue_id => running_entry})
      |> Map.put(:claimed, MapSet.new([issue_id]))
      |> Map.put(:retry_attempts, %{})
    end)

    send(pid, {:DOWN, ref, :process, self(), :boom})
    Process.sleep(50)
    state = :sys.get_state(pid)

    assert %{attempt: 1, due_at_ms: due_at_ms, identifier: "MT-560", error: "agent exited: :boom"} =
             state.retry_attempts[issue_id]

    assert_due_in_range(due_at_ms, 9_000, 10_500)
  end

  defp assert_due_in_range(due_at_ms, min_remaining_ms, max_remaining_ms) do
    remaining_ms = due_at_ms - System.monotonic_time(:millisecond)

    assert remaining_ms >= min_remaining_ms
    assert remaining_ms <= max_remaining_ms
  end

  test "fetch issues by states with empty state set is a no-op" do
    assert {:ok, []} = Client.fetch_issues_by_states([])
  end

  test "prompt builder renders issue and attempt values from workflow template" do
    workflow_prompt =
      "Ticket {{ issue.identifier }} {{ issue.title }} labels={{ issue.labels }} attempt={{ attempt }}"

    write_workflow_file!(Workflow.workflow_file_path(), prompt: workflow_prompt)

    issue = %Issue{
      identifier: "S-1",
      title: "Refactor backend request path",
      description: "Replace transport layer",
      state: "Todo",
      url: "https://example.org/issues/S-1",
      labels: ["backend"]
    }

    prompt = PromptBuilder.build_prompt(issue, attempt: 3)

    assert prompt =~ "Ticket S-1 Refactor backend request path"
    assert prompt =~ "labels=backend"
    assert prompt =~ "attempt=3"
  end

  test "prompt builder renders issue datetime fields without crashing" do
    workflow_prompt = "Ticket {{ issue.identifier }} created={{ issue.created_at }} updated={{ issue.updated_at }}"

    write_workflow_file!(Workflow.workflow_file_path(), prompt: workflow_prompt)

    created_at = DateTime.from_naive!(~N[2026-02-26 18:06:48], "Etc/UTC")
    updated_at = DateTime.from_naive!(~N[2026-02-26 18:07:03], "Etc/UTC")

    issue = %Issue{
      identifier: "MT-697",
      title: "Live smoke",
      description: "Prompt should serialize datetimes",
      state: "Todo",
      url: "https://example.org/issues/MT-697",
      labels: [],
      created_at: created_at,
      updated_at: updated_at
    }

    prompt = PromptBuilder.build_prompt(issue)

    assert prompt =~ "Ticket MT-697"
    assert prompt =~ "created=2026-02-26T18:06:48Z"
    assert prompt =~ "updated=2026-02-26T18:07:03Z"
  end

  test "prompt builder normalizes nested date-like values, maps, and structs in issue fields" do
    write_workflow_file!(Workflow.workflow_file_path(), prompt: "Ticket {{ issue.identifier }}")

    issue = %Issue{
      identifier: "MT-701",
      title: "Serialize nested values",
      description: "Prompt builder should normalize nested terms",
      state: "Todo",
      url: "https://example.org/issues/MT-701",
      labels: [
        ~N[2026-02-27 12:34:56],
        ~D[2026-02-28],
        ~T[12:34:56],
        %{phase: "test"},
        URI.parse("https://example.org/issues/MT-701")
      ]
    }

    assert PromptBuilder.build_prompt(issue) == "Ticket MT-701"
  end

  test "prompt builder uses strict variable rendering" do
    workflow_prompt = "Work on ticket {{ missing.ticket_id }} and follow these steps."

    write_workflow_file!(Workflow.workflow_file_path(), prompt: workflow_prompt)

    issue = %Issue{
      identifier: "MT-123",
      title: "Investigate broken sync",
      description: "Reproduce and fix",
      state: "In Progress",
      url: "https://example.org/issues/MT-123",
      labels: ["bug"]
    }

    assert_raise Solid.RenderError, fn ->
      PromptBuilder.build_prompt(issue)
    end
  end

  test "prompt builder surfaces invalid template content with prompt context" do
    write_workflow_file!(Workflow.workflow_file_path(), prompt: "{% if issue.identifier %}")

    issue = %Issue{
      identifier: "MT-999",
      title: "Broken prompt",
      description: "Invalid template syntax",
      state: "Todo",
      url: "https://example.org/issues/MT-999",
      labels: []
    }

    assert_raise RuntimeError, ~r/template_parse_error:.*template="/s, fn ->
      PromptBuilder.build_prompt(issue)
    end
  end

  test "prompt builder uses a sensible default template when workflow prompt is blank" do
    write_workflow_file!(Workflow.workflow_file_path(), prompt: "   \n")

    issue = %Issue{
      identifier: "MT-777",
      title: "Make fallback prompt useful",
      description: "Include enough issue context to start working.",
      state: "In Progress",
      url: "https://example.org/issues/MT-777",
      labels: ["prompt"]
    }

    prompt = PromptBuilder.build_prompt(issue)

    assert prompt =~ "You are working on a Linear issue."
    assert prompt =~ "Identifier: MT-777"
    assert prompt =~ "Title: Make fallback prompt useful"
    assert prompt =~ "Body:"
    assert prompt =~ "Include enough issue context to start working."
    assert Config.workflow_prompt() =~ "{{ issue.identifier }}"
    assert Config.workflow_prompt() =~ "{{ issue.title }}"
    assert Config.workflow_prompt() =~ "{{ issue.description }}"
  end

  test "prompt builder default template handles missing issue body" do
    write_workflow_file!(Workflow.workflow_file_path(), prompt: "")

    issue = %Issue{
      identifier: "MT-778",
      title: "Handle empty body",
      description: nil,
      state: "Todo",
      url: "https://example.org/issues/MT-778",
      labels: []
    }

    prompt = PromptBuilder.build_prompt(issue)

    assert prompt =~ "Identifier: MT-778"
    assert prompt =~ "Title: Handle empty body"
    assert prompt =~ "No description provided."
  end

  test "prompt builder reports workflow load failures separately from template parse errors" do
    original_workflow_path = Workflow.workflow_file_path()
    workflow_store_pid = Process.whereis(SymphonyElixir.WorkflowStore)

    on_exit(fn ->
      Workflow.set_workflow_file_path(original_workflow_path)

      if is_pid(workflow_store_pid) and is_nil(Process.whereis(SymphonyElixir.WorkflowStore)) do
        Supervisor.restart_child(SymphonyElixir.Supervisor, SymphonyElixir.WorkflowStore)
      end
    end)

    assert :ok = Supervisor.terminate_child(SymphonyElixir.Supervisor, SymphonyElixir.WorkflowStore)

    Workflow.set_workflow_file_path(Path.join(System.tmp_dir!(), "missing-workflow-#{System.unique_integer([:positive])}.md"))

    issue = %Issue{
      identifier: "MT-780",
      title: "Workflow unavailable",
      description: "Missing workflow file",
      state: "Todo",
      url: "https://example.org/issues/MT-780",
      labels: []
    }

    assert_raise RuntimeError, ~r/workflow_unavailable:/, fn ->
      PromptBuilder.build_prompt(issue)
    end
  end

  test "in-repo WORKFLOW.md renders correctly" do
    workflow_path = Workflow.workflow_file_path()
    Workflow.set_workflow_file_path(Path.expand("WORKFLOW.md", File.cwd!()))

    issue = %Issue{
      identifier: "MT-616",
      title: "Use rich templates for WORKFLOW.md",
      description: "Render with rich template variables",
      state: "In Progress",
      url: "https://example.org/issues/MT-616/use-rich-templates-for-workflowmd",
      labels: ["templating", "workflow"]
    }

    on_exit(fn -> Workflow.set_workflow_file_path(workflow_path) end)

    prompt = PromptBuilder.build_prompt(issue, attempt: 2)

    assert prompt =~ "You are working on a Linear ticket `MT-616`"
    assert prompt =~ "Issue context:"
    assert prompt =~ "Identifier: MT-616"
    assert prompt =~ "Title: Use rich templates for WORKFLOW.md"
    assert prompt =~ "Current status: In Progress"
    assert prompt =~ "https://example.org/issues/MT-616/use-rich-templates-for-workflowmd"
    assert prompt =~ "This is an unattended orchestration session."
    assert prompt =~ "Only stop early for a true blocker"
    assert prompt =~ "Do not include \"next steps for user\""
    assert prompt =~ "open and follow `.codex/skills/land/SKILL.md`"
    assert prompt =~ "Do not call `gh pr merge` directly"
    assert prompt =~ "Continuation context:"
    assert prompt =~ "retry attempt #2"
  end

  test "prompt builder adds continuation guidance for retries" do
    workflow_prompt = "{% if attempt %}Retry #" <> "{{ attempt }}" <> "{% endif %}"
    write_workflow_file!(Workflow.workflow_file_path(), prompt: workflow_prompt)

    issue = %Issue{
      identifier: "MT-201",
      title: "Continue autonomous ticket",
      description: "Retry flow",
      state: "In Progress",
      url: "https://example.org/issues/MT-201",
      labels: []
    }

    prompt = PromptBuilder.build_prompt(issue, attempt: 2)

    assert prompt == "Retry #2"
  end

  test "prompt builder supports continuation summary mode" do
    issue = %Issue{
      identifier: "MT-301",
      title: "Resume with artifacts",
      description: "Use workspace artifacts instead of old thread history",
      state: "In Progress",
      url: "https://example.org/issues/MT-301",
      labels: []
    }

    prompt =
      PromptBuilder.build_prompt(issue,
        prompt_mode: :continuation_summary,
        turn_number: 2,
        max_turns: 3
      )

    assert prompt =~ "Continuation summary:"
    assert prompt =~ "Continuation turn #2 of 3"
    assert prompt =~ "shared/context_summary.md"
    assert prompt =~ "shared/guardrail_state.json"
    assert prompt =~ "Do not assume the full prior thread history is available"
  end

  test "prompt builder rejects unsupported prompt modes" do
    issue = %Issue{
      identifier: "MT-302",
      title: "Unsupported mode",
      description: "Prompt mode validation",
      state: "In Progress",
      url: "https://example.org/issues/MT-302",
      labels: []
    }

    assert_raise ArgumentError, ~r/unsupported_prompt_mode/, fn ->
      PromptBuilder.build_prompt(issue, prompt_mode: :mystery)
    end
  end

  test "agent runner keeps workspace after successful codex run" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-agent-runner-retain-workspace-#{System.unique_integer([:positive])}"
      )

    try do
      template_repo = Path.join(test_root, "source")
      workspace_root = Path.join(test_root, "workspaces")
      codex_binary = Path.join(test_root, "fake-codex")

      File.mkdir_p!(template_repo)
      File.mkdir_p!(workspace_root)
      File.write!(Path.join(template_repo, "README.md"), "# test")
      System.cmd("git", ["-C", template_repo, "init", "-b", "main"])
      System.cmd("git", ["-C", template_repo, "config", "user.name", "Test User"])
      System.cmd("git", ["-C", template_repo, "config", "user.email", "test@example.com"])
      System.cmd("git", ["-C", template_repo, "add", "README.md"])
      System.cmd("git", ["-C", template_repo, "commit", "-m", "initial"])

      File.write!(codex_binary, """
      #!/bin/sh
      count=0
      while IFS= read -r line; do
        count=$((count + 1))
        case "$count" in
          1)
            printf '%s\\n' '{\"id\":1,\"result\":{}}'
            ;;
          2)
            ;;
          3)
            printf '%s\\n' '{\"id\":2,\"result\":{\"thread\":{\"id\":\"thread-1\"}}}'
            ;;
          4)
            printf '%s\\n' '{\"id\":3,\"result\":{\"turn\":{\"id\":\"turn-1\"}}}'
            printf '%s\\n' '{\"method\":\"turn/completed\"}'
            exit 0
            ;;
          *)
            ;;
        esac
      done
      """)

      File.chmod!(codex_binary, 0o755)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        hook_after_create: "cp #{Path.join(template_repo, "README.md")} README.md",
        codex_command: "#{codex_binary} app-server"
      )

      issue = %Issue{
        identifier: "S-99",
        title: "Smoke test",
        description: "Run and keep workspace",
        state: "In Progress",
        url: "https://example.org/issues/S-99",
        labels: ["backend"]
      }

      before = MapSet.new(File.ls!(workspace_root))
      assert :ok = AgentRunner.run(issue)
      entries_after = MapSet.new(File.ls!(workspace_root))

      created =
        MapSet.difference(entries_after, before) |> Enum.filter(&(&1 == "S-99"))

      created = MapSet.new(created)

      assert MapSet.size(created) == 1
      workspace_name = created |> Enum.to_list() |> List.first()
      assert workspace_name == "S-99"

      workspace = Path.join(workspace_root, workspace_name)
      assert File.exists?(workspace)
      assert File.exists?(Path.join(workspace, "README.md"))
    after
      File.rm_rf(test_root)
    end
  end

  test "agent runner forwards timestamped codex updates to recipient" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-agent-runner-updates-#{System.unique_integer([:positive])}"
      )

    try do
      template_repo = Path.join(test_root, "source")
      workspace_root = Path.join(test_root, "workspaces")
      codex_binary = Path.join(test_root, "fake-codex")

      File.mkdir_p!(template_repo)
      File.write!(Path.join(template_repo, "README.md"), "# test")
      System.cmd("git", ["-C", template_repo, "init", "-b", "main"])
      System.cmd("git", ["-C", template_repo, "config", "user.name", "Test User"])
      System.cmd("git", ["-C", template_repo, "config", "user.email", "test@example.com"])
      System.cmd("git", ["-C", template_repo, "add", "README.md"])
      System.cmd("git", ["-C", template_repo, "commit", "-m", "initial"])

      File.write!(
        codex_binary,
        """
        #!/bin/sh
        count=0
        while IFS= read -r line; do
          count=$((count + 1))
          case "$count" in
            1)
              printf '%s\\n' '{\"id\":1,\"result\":{}}'
              ;;
            2)
              printf '%s\\n' '{\"id\":2,\"result\":{\"thread\":{\"id\":\"thread-live\"}}}'
              ;;
            3)
              printf '%s\\n' '{\"id\":3,\"result\":{\"turn\":{\"id\":\"turn-live\"}}}'
              ;;
            4)
              printf '%s\\n' '{\"method\":\"turn/completed\"}'
              ;;
            *)
              ;;
          esac
        done
        """
      )

      File.chmod!(codex_binary, 0o755)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        hook_after_create: "cp #{Path.join(template_repo, "README.md")} README.md",
        codex_command: "#{codex_binary} app-server"
      )

      issue = %Issue{
        id: "issue-live-updates",
        identifier: "MT-99",
        title: "Smoke test",
        description: "Capture codex updates",
        state: "In Progress",
        url: "https://example.org/issues/MT-99",
        labels: ["backend"]
      }

      test_pid = self()

      assert :ok =
               AgentRunner.run(
                 issue,
                 test_pid,
                 issue_state_fetcher: fn [_issue_id] -> {:ok, [%{issue | state: "Done"}]} end
               )

      assert_receive {:codex_worker_update, "issue-live-updates",
                      %{
                        event: :session_started,
                        timestamp: %DateTime{},
                        session_id: session_id
                      }},
                     500

      assert session_id == "thread-live-turn-live"
    after
      File.rm_rf(test_root)
    end
  end

  test "agent runner continues with a follow-up turn while the issue remains active" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-agent-runner-continuation-#{System.unique_integer([:positive])}"
      )

    try do
      template_repo = Path.join(test_root, "source")
      workspace_root = Path.join(test_root, "workspaces")
      codex_binary = Path.join(test_root, "fake-codex")
      trace_file = Path.join(test_root, "codex.trace")

      File.mkdir_p!(template_repo)
      File.write!(Path.join(template_repo, "README.md"), "# test")
      System.cmd("git", ["-C", template_repo, "init", "-b", "main"])
      System.cmd("git", ["-C", template_repo, "config", "user.name", "Test User"])
      System.cmd("git", ["-C", template_repo, "config", "user.email", "test@example.com"])
      System.cmd("git", ["-C", template_repo, "add", "README.md"])
      System.cmd("git", ["-C", template_repo, "commit", "-m", "initial"])

      File.write!(codex_binary, """
      #!/bin/sh
      trace_file="${SYMP_TEST_CODEx_TRACE:-/tmp/codex.trace}"
      run_id="$(date +%s%N)-$$"
      printf 'RUN:%s\\n' "$run_id" >> "$trace_file"
      count=0

      while IFS= read -r line; do
        count=$((count + 1))
        printf 'JSON:%s\\n' "$line" >> "$trace_file"
        case "$count" in
          1)
            printf '%s\\n' '{"id":1,"result":{}}'
            ;;
          2)
            ;;
          3)
            printf '%s\\n' '{"id":2,"result":{"thread":{"id":"thread-cont"}}}'
            ;;
          4)
            printf '%s\\n' '{"id":3,"result":{"turn":{"id":"turn-cont-1"}}}'
            printf '%s\\n' '{"method":"turn/completed"}'
            ;;
          5)
            printf '%s\\n' '{"id":3,"result":{"turn":{"id":"turn-cont-2"}}}'
            printf '%s\\n' '{"method":"turn/completed"}'
            ;;
        esac
      done
      """)

      File.chmod!(codex_binary, 0o755)
      System.put_env("SYMP_TEST_CODEx_TRACE", trace_file)

      on_exit(fn -> System.delete_env("SYMP_TEST_CODEx_TRACE") end)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        hook_after_create: "cp #{Path.join(template_repo, "README.md")} README.md",
        codex_command: "#{codex_binary} app-server",
        max_turns: 3
      )

      parent = self()

      state_fetcher = fn [_issue_id] ->
        attempt = Process.get(:agent_turn_fetch_count, 0) + 1
        Process.put(:agent_turn_fetch_count, attempt)
        send(parent, {:issue_state_fetch, attempt})

        state =
          if attempt == 1 do
            "In Progress"
          else
            "Done"
          end

        {:ok,
         [
           %Issue{
             id: "issue-continue",
             identifier: "MT-247",
             title: "Continue until done",
             description: "Still active after first turn",
             state: state
           }
         ]}
      end

      issue = %Issue{
        id: "issue-continue",
        identifier: "MT-247",
        title: "Continue until done",
        description: "Still active after first turn",
        state: "In Progress",
        url: "https://example.org/issues/MT-247",
        labels: []
      }

      assert :ok = AgentRunner.run(issue, nil, issue_state_fetcher: state_fetcher)
      assert_receive {:issue_state_fetch, 1}
      assert_receive {:issue_state_fetch, 2}

      lines = File.read!(trace_file) |> String.split("\n", trim: true)

      assert length(Enum.filter(lines, &String.starts_with?(&1, "RUN:"))) == 1
      assert length(Enum.filter(lines, &String.contains?(&1, "\"method\":\"thread/start\""))) == 1

      turn_texts =
        lines
        |> Enum.filter(&String.starts_with?(&1, "JSON:"))
        |> Enum.map(&String.trim_leading(&1, "JSON:"))
        |> Enum.map(&Jason.decode!/1)
        |> Enum.filter(&(&1["method"] == "turn/start"))
        |> Enum.map(fn payload ->
          get_in(payload, ["params", "input"])
          |> Enum.map_join("\n", &Map.get(&1, "text", ""))
        end)

      assert length(turn_texts) == 2
      assert Enum.at(turn_texts, 0) =~ "You are an agent for this repository."
      refute Enum.at(turn_texts, 1) =~ "You are an agent for this repository."
      assert Enum.at(turn_texts, 1) =~ "Continuation summary:"
      assert Enum.at(turn_texts, 1) =~ "Continuation turn #2 of 3"
      assert Enum.at(turn_texts, 1) =~ "shared/context_summary.md"
      assert Enum.at(turn_texts, 1) =~ "shared/guardrail_state.json"

      refute Enum.at(turn_texts, 1) =~
               "original task instructions and prior turn context are already present in this thread"

      workspace = Path.join(workspace_root, issue.identifier)
      context_summary = Path.join([workspace, "shared", "context_summary.md"])
      guardrail_state_path = Path.join([workspace, "shared", "guardrail_state.json"])

      assert File.exists?(context_summary)
      assert File.exists?(guardrail_state_path)
      assert File.read!(context_summary) =~ "Prompt mode: continuation_summary"

      guardrail_state = Jason.decode!(File.read!(guardrail_state_path))
      assert guardrail_state["kind"] == "continuation_artifact"
      assert guardrail_state["issue_id"] == "issue-continue"
      assert guardrail_state["identifier"] == "MT-247"
      assert guardrail_state["prompt_mode"] == "continuation_summary"
      assert guardrail_state["turn_number"] == 2
      assert guardrail_state["max_turns"] == 3
      assert guardrail_state["context_summary_path"] == "shared/context_summary.md"
    after
      System.delete_env("SYMP_TEST_CODEx_TRACE")
      File.rm_rf(test_root)
    end
  end

  test "agent runner asks the continuation decider between completed turns" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-agent-runner-gate-#{System.unique_integer([:positive])}"
      )

    try do
      template_repo = Path.join(test_root, "source")
      workspace_root = Path.join(test_root, "workspaces")
      codex_binary = Path.join(test_root, "fake-codex")
      trace_file = Path.join(test_root, "codex.trace")

      File.mkdir_p!(template_repo)
      File.write!(Path.join(template_repo, "README.md"), "# test")
      System.cmd("git", ["-C", template_repo, "init", "-b", "main"])
      System.cmd("git", ["-C", template_repo, "config", "user.name", "Test User"])
      System.cmd("git", ["-C", template_repo, "config", "user.email", "test@example.com"])
      System.cmd("git", ["-C", template_repo, "add", "README.md"])
      System.cmd("git", ["-C", template_repo, "commit", "-m", "initial"])

      File.write!(codex_binary, """
      #!/bin/sh
      trace_file="${SYMP_TEST_CODEx_TRACE:-/tmp/codex.trace}"
      printf 'RUN\\n' >> "$trace_file"
      count=0

      while IFS= read -r line; do
        count=$((count + 1))
        printf 'JSON:%s\\n' "$line" >> "$trace_file"
        case "$count" in
          1)
            printf '%s\\n' '{"id":1,"result":{}}'
            ;;
          2)
            ;;
          3)
            printf '%s\\n' '{"id":2,"result":{"thread":{"id":"thread-gate"}}}'
            ;;
          4)
            printf '%s\\n' '{"id":3,"result":{"turn":{"id":"turn-gate-1"}}}'
            printf '%s\\n' '{"method":"turn/completed"}'
            ;;
          5)
            printf '%s\\n' '{"id":3,"result":{"turn":{"id":"turn-gate-2"}}}'
            printf '%s\\n' '{"method":"turn/completed"}'
            ;;
        esac
      done
      """)

      File.chmod!(codex_binary, 0o755)
      System.put_env("SYMP_TEST_CODEx_TRACE", trace_file)

      on_exit(fn -> System.delete_env("SYMP_TEST_CODEx_TRACE") end)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        hook_after_create: "cp #{Path.join(template_repo, "README.md")} README.md",
        codex_command: "#{codex_binary} app-server",
        max_turns: 3
      )

      parent = self()

      continuation_decider = fn %Issue{id: issue_id} = issue, turn_number ->
        send(parent, {:continuation_request, issue_id, turn_number})

        if turn_number == 1 do
          {:allow, :probe, issue}
        else
          {:deny, :issue_not_active}
        end
      end

      issue = %Issue{
        id: "issue-gated-continue",
        identifier: "MT-249",
        title: "Continue with gate",
        description: "Continuation requires orchestrator approval",
        state: "In Progress",
        url: "https://example.org/issues/MT-249",
        labels: []
      }

      assert :ok = AgentRunner.run(issue, nil, continuation_decider: continuation_decider)
      assert_receive {:continuation_request, "issue-gated-continue", 1}
      assert_receive {:continuation_request, "issue-gated-continue", 2}

      trace = File.read!(trace_file)
      assert length(Regex.scan(~r/"method":"turn\/start"/, trace)) == 2
    after
      System.delete_env("SYMP_TEST_CODEx_TRACE")
      File.rm_rf(test_root)
    end
  end

  test "agent runner uses a fresh summary session for high-risk continuation" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-agent-runner-fresh-summary-#{System.unique_integer([:positive])}"
      )

    try do
      template_repo = Path.join(test_root, "source")
      workspace_root = Path.join(test_root, "workspaces")
      codex_binary = Path.join(test_root, "fake-codex")
      trace_file = Path.join(test_root, "codex.trace")

      File.mkdir_p!(template_repo)
      File.write!(Path.join(template_repo, "README.md"), "# test")
      System.cmd("git", ["-C", template_repo, "init", "-b", "main"])
      System.cmd("git", ["-C", template_repo, "config", "user.name", "Test User"])
      System.cmd("git", ["-C", template_repo, "config", "user.email", "test@example.com"])
      System.cmd("git", ["-C", template_repo, "add", "README.md"])
      System.cmd("git", ["-C", template_repo, "commit", "-m", "initial"])

      File.write!(codex_binary, """
      #!/bin/sh
      trace_file="${SYMP_TEST_CODEx_TRACE:-/tmp/codex.trace}"
      session_marker="$(date +%s%N)-$$"
      printf 'RUN:%s\\n' "$session_marker" >> "$trace_file"
      count=0

      while IFS= read -r line; do
        count=$((count + 1))
        printf 'JSON:%s\\n' "$line" >> "$trace_file"
        case "$count" in
          1)
            printf '%s\\n' '{"id":1,"result":{}}'
            ;;
          2)
            ;;
          3)
            printf '%s\\n' '{"id":2,"result":{"thread":{"id":"thread-fresh"}}}'
            ;;
          4)
            printf '%s\\n' '{"id":3,"result":{"turn":{"id":"turn-fresh-1"}}}'
            printf '%s\\n' '{"method":"turn/completed"}'
            ;;
        esac
      done
      """)

      File.chmod!(codex_binary, 0o755)
      System.put_env("SYMP_TEST_CODEx_TRACE", trace_file)

      on_exit(fn -> System.delete_env("SYMP_TEST_CODEx_TRACE") end)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        hook_after_create: "cp #{Path.join(template_repo, "README.md")} README.md",
        codex_command: "#{codex_binary} app-server",
        max_turns: 3
      )

      parent = self()

      continuation_decider = fn %Issue{id: issue_id} = issue, turn_number ->
        send(parent, {:continuation_request, issue_id, turn_number})

        if turn_number == 1 do
          {:allow, :default, :fresh_summary, issue}
        else
          {:deny, :issue_not_active}
        end
      end

      issue = %Issue{
        id: "issue-fresh-summary-runner",
        identifier: "MT-250",
        title: "Fresh summary continuation",
        description: "High-risk continuation should start a new session",
        state: "In Progress",
        url: "https://example.org/issues/MT-250",
        labels: []
      }

      assert :ok = AgentRunner.run(issue, nil, continuation_decider: continuation_decider)
      assert_receive {:continuation_request, "issue-fresh-summary-runner", 1}
      assert_receive {:continuation_request, "issue-fresh-summary-runner", 2}

      trace = File.read!(trace_file)
      assert length(Regex.scan(~r/"method":"thread\/start"/, trace)) == 2

      turn_texts =
        trace
        |> String.split("\n", trim: true)
        |> Enum.filter(&String.starts_with?(&1, "JSON:"))
        |> Enum.map(&String.trim_leading(&1, "JSON:"))
        |> Enum.map(&Jason.decode!/1)
        |> Enum.filter(&(&1["method"] == "turn/start"))
        |> Enum.map(fn payload ->
          get_in(payload, ["params", "input"])
          |> Enum.map_join("\n", &Map.get(&1, "text", ""))
        end)

      assert length(turn_texts) == 2
      assert Enum.at(turn_texts, 1) =~ "Continuation summary:"
      assert Enum.at(turn_texts, 1) =~ "shared/context_summary.md"
    after
      System.delete_env("SYMP_TEST_CODEx_TRACE")
      File.rm_rf(test_root)
    end
  end

  test "agent runner stops continuing once agent.max_turns is reached" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-agent-runner-max-turns-#{System.unique_integer([:positive])}"
      )

    try do
      template_repo = Path.join(test_root, "source")
      workspace_root = Path.join(test_root, "workspaces")
      codex_binary = Path.join(test_root, "fake-codex")
      trace_file = Path.join(test_root, "codex.trace")

      File.mkdir_p!(template_repo)
      File.write!(Path.join(template_repo, "README.md"), "# test")
      System.cmd("git", ["-C", template_repo, "init", "-b", "main"])
      System.cmd("git", ["-C", template_repo, "config", "user.name", "Test User"])
      System.cmd("git", ["-C", template_repo, "config", "user.email", "test@example.com"])
      System.cmd("git", ["-C", template_repo, "add", "README.md"])
      System.cmd("git", ["-C", template_repo, "commit", "-m", "initial"])

      File.write!(codex_binary, """
      #!/bin/sh
      trace_file="${SYMP_TEST_CODEx_TRACE:-/tmp/codex.trace}"
      printf 'RUN\\n' >> "$trace_file"
      count=0

      while IFS= read -r line; do
        count=$((count + 1))
        printf 'JSON:%s\\n' "$line" >> "$trace_file"
        case "$count" in
          1)
            printf '%s\\n' '{"id":1,"result":{}}'
            ;;
          2)
            ;;
          3)
            printf '%s\\n' '{"id":2,"result":{"thread":{"id":"thread-max"}}}'
            ;;
          4)
            printf '%s\\n' '{"id":3,"result":{"turn":{"id":"turn-max-1"}}}'
            printf '%s\\n' '{"method":"turn/completed"}'
            ;;
          5)
            printf '%s\\n' '{"id":3,"result":{"turn":{"id":"turn-max-2"}}}'
            printf '%s\\n' '{"method":"turn/completed"}'
            ;;
        esac
      done
      """)

      File.chmod!(codex_binary, 0o755)
      System.put_env("SYMP_TEST_CODEx_TRACE", trace_file)

      on_exit(fn -> System.delete_env("SYMP_TEST_CODEx_TRACE") end)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        hook_after_create: "cp #{Path.join(template_repo, "README.md")} README.md",
        codex_command: "#{codex_binary} app-server",
        max_turns: 2
      )

      state_fetcher = fn [_issue_id] ->
        {:ok,
         [
           %Issue{
             id: "issue-max-turns",
             identifier: "MT-248",
             title: "Stop at max turns",
             description: "Still active",
             state: "In Progress"
           }
         ]}
      end

      issue = %Issue{
        id: "issue-max-turns",
        identifier: "MT-248",
        title: "Stop at max turns",
        description: "Still active",
        state: "In Progress",
        url: "https://example.org/issues/MT-248",
        labels: []
      }

      assert :ok = AgentRunner.run(issue, nil, issue_state_fetcher: state_fetcher)

      trace = File.read!(trace_file)
      assert length(String.split(trace, "RUN", trim: true)) == 1
      assert length(Regex.scan(~r/"method":"turn\/start"/, trace)) == 2
    after
      System.delete_env("SYMP_TEST_CODEx_TRACE")
      File.rm_rf(test_root)
    end
  end

  test "app server starts with workspace cwd and expected startup command" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-app-server-args-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      workspace = Path.join(workspace_root, "MT-77")
      codex_binary = Path.join(test_root, "fake-codex")
      trace_file = Path.join(test_root, "codex-args.trace")
      previous_trace = System.get_env("SYMP_TEST_CODex_TRACE")

      on_exit(fn ->
        if is_binary(previous_trace) do
          System.put_env("SYMP_TEST_CODex_TRACE", previous_trace)
        else
          System.delete_env("SYMP_TEST_CODex_TRACE")
        end
      end)

      System.put_env("SYMP_TEST_CODex_TRACE", trace_file)
      File.mkdir_p!(workspace)

      File.write!(codex_binary, """
      #!/bin/sh
      trace_file="${SYMP_TEST_CODex_TRACE:-/tmp/codex-args.trace}"
      count=0
      printf 'ARGV:%s\\n' \"$*\" >> \"$trace_file\"
      printf 'CWD:%s\\n' \"$PWD\" >> \"$trace_file\"

      while IFS= read -r line; do
        count=$((count + 1))
        printf 'JSON:%s\\n' \"$line\" >> \"$trace_file\"
        case \"$count\" in
          1)
            printf '%s\\n' '{\"id\":1,\"result\":{}}'
            ;;
          2)
            printf '%s\\n' '{\"id\":2,\"result\":{\"thread\":{\"id\":\"thread-77\"}}}'
            ;;
          3)
            printf '%s\\n' '{\"id\":3,\"result\":{\"turn\":{\"id\":\"turn-77\"}}}'
            ;;
          4)
            printf '%s\\n' '{\"method\":\"turn/completed\"}'
            exit 0
            ;;
          *)
            exit 0
            ;;
        esac
      done
      """)

      File.chmod!(codex_binary, 0o755)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        codex_command: "#{codex_binary} app-server"
      )

      issue = %Issue{
        id: "issue-args",
        identifier: "MT-77",
        title: "Validate codex args",
        description: "Check startup args and cwd",
        state: "In Progress",
        url: "https://example.org/issues/MT-77",
        labels: ["backend"]
      }

      assert {:ok, _result} = AppServer.run(workspace, "Fix workspace start args", issue)

      trace = File.read!(trace_file)
      lines = String.split(trace, "\n", trim: true)

      assert argv_line = Enum.find(lines, fn line -> String.starts_with?(line, "ARGV:") end)
      assert String.contains?(argv_line, "app-server")
      refute Enum.any?(lines, &String.contains?(&1, "--yolo"))
      assert cwd_line = Enum.find(lines, fn line -> String.starts_with?(line, "CWD:") end)
      assert String.ends_with?(cwd_line, Path.basename(workspace))

      assert Enum.any?(lines, fn line ->
               if String.starts_with?(line, "JSON:") do
                 line
                 |> String.trim_leading("JSON:")
                 |> Jason.decode!()
                 |> then(fn payload ->
                   expected_approval_policy = %{
                     "reject" => %{
                       "sandbox_approval" => true,
                       "rules" => true,
                       "mcp_elicitations" => true
                     }
                   }

                   payload["method"] == "thread/start" &&
                     get_in(payload, ["params", "approvalPolicy"]) == expected_approval_policy &&
                     get_in(payload, ["params", "sandbox"]) == "workspace-write" &&
                     get_in(payload, ["params", "cwd"]) == Path.expand(workspace)
                 end)
               else
                 false
               end
             end)

      expected_turn_sandbox_policy = %{
        "type" => "workspaceWrite",
        "writableRoots" => [Path.expand(workspace)],
        "readOnlyAccess" => %{"type" => "fullAccess"},
        "networkAccess" => false,
        "excludeTmpdirEnvVar" => false,
        "excludeSlashTmp" => false
      }

      assert Enum.any?(lines, fn line ->
               if String.starts_with?(line, "JSON:") do
                 line
                 |> String.trim_leading("JSON:")
                 |> Jason.decode!()
                 |> then(fn payload ->
                   expected_approval_policy = %{
                     "reject" => %{
                       "sandbox_approval" => true,
                       "rules" => true,
                       "mcp_elicitations" => true
                     }
                   }

                   payload["method"] == "turn/start" &&
                     get_in(payload, ["params", "cwd"]) == Path.expand(workspace) &&
                     get_in(payload, ["params", "approvalPolicy"]) == expected_approval_policy &&
                     get_in(payload, ["params", "sandboxPolicy"]) == expected_turn_sandbox_policy
                 end)
               else
                 false
               end
             end)
    after
      File.rm_rf(test_root)
    end
  end

  test "app server startup command supports codex args override from workflow config" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-app-server-custom-args-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      workspace = Path.join(workspace_root, "MT-88")
      codex_binary = Path.join(test_root, "fake-codex")
      trace_file = Path.join(test_root, "codex-custom-args.trace")
      previous_trace = System.get_env("SYMP_TEST_CODex_TRACE")

      on_exit(fn ->
        if is_binary(previous_trace) do
          System.put_env("SYMP_TEST_CODex_TRACE", previous_trace)
        else
          System.delete_env("SYMP_TEST_CODex_TRACE")
        end
      end)

      System.put_env("SYMP_TEST_CODex_TRACE", trace_file)
      File.mkdir_p!(workspace)

      File.write!(codex_binary, """
      #!/bin/sh
      trace_file="${SYMP_TEST_CODex_TRACE:-/tmp/codex-custom-args.trace}"
      count=0
      printf 'ARGV:%s\\n' \"$*\" >> \"$trace_file\"

      while IFS= read -r line; do
        count=$((count + 1))
        case \"$count\" in
          1)
            printf '%s\\n' '{\"id\":1,\"result\":{}}'
            ;;
          2)
            printf '%s\\n' '{\"id\":2,\"result\":{\"thread\":{\"id\":\"thread-88\"}}}'
            ;;
          3)
            printf '%s\\n' '{\"id\":3,\"result\":{\"turn\":{\"id\":\"turn-88\"}}}'
            ;;
          4)
            printf '%s\\n' '{\"method\":\"turn/completed\"}'
            exit 0
            ;;
          *)
            exit 0
            ;;
        esac
      done
      """)

      File.chmod!(codex_binary, 0o755)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        codex_command: "#{codex_binary} --model gpt-5.3-codex app-server"
      )

      issue = %Issue{
        id: "issue-custom-args",
        identifier: "MT-88",
        title: "Validate custom codex args",
        description: "Check startup args override",
        state: "In Progress",
        url: "https://example.org/issues/MT-88",
        labels: ["backend"]
      }

      assert {:ok, _result} = AppServer.run(workspace, "Fix workspace start args", issue)

      trace = File.read!(trace_file)
      lines = String.split(trace, "\n", trim: true)

      assert argv_line = Enum.find(lines, fn line -> String.starts_with?(line, "ARGV:") end)
      assert String.contains?(argv_line, "--model gpt-5.3-codex app-server")
      refute String.contains?(argv_line, "--ask-for-approval never")
      refute String.contains?(argv_line, "--sandbox danger-full-access")
    after
      File.rm_rf(test_root)
    end
  end

  test "app server startup payload uses configurable approval and sandbox settings from workflow config" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-app-server-policy-overrides-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      workspace = Path.join(workspace_root, "MT-99")
      codex_binary = Path.join(test_root, "fake-codex")
      trace_file = Path.join(test_root, "codex-policy-overrides.trace")
      previous_trace = System.get_env("SYMP_TEST_CODex_TRACE")

      on_exit(fn ->
        if is_binary(previous_trace) do
          System.put_env("SYMP_TEST_CODex_TRACE", previous_trace)
        else
          System.delete_env("SYMP_TEST_CODex_TRACE")
        end
      end)

      System.put_env("SYMP_TEST_CODex_TRACE", trace_file)
      File.mkdir_p!(workspace)

      File.write!(codex_binary, """
      #!/bin/sh
      trace_file="${SYMP_TEST_CODex_TRACE:-/tmp/codex-policy-overrides.trace}"
      count=0

      while IFS= read -r line; do
        count=$((count + 1))
        printf 'JSON:%s\\n' "$line" >> "$trace_file"

        case "$count" in
          1)
            printf '%s\\n' '{"id":1,"result":{}}'
            ;;
          2)
            printf '%s\\n' '{"id":2,"result":{"thread":{"id":"thread-99"}}}'
            ;;
          3)
            printf '%s\\n' '{"id":3,"result":{"turn":{"id":"turn-99"}}}'
            ;;
          4)
            printf '%s\\n' '{"method":"turn/completed"}'
            exit 0
            ;;
          *)
            exit 0
            ;;
        esac
      done
      """)

      File.chmod!(codex_binary, 0o755)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        codex_command: "#{codex_binary} app-server",
        codex_approval_policy: "on-request",
        codex_thread_sandbox: "workspace-write",
        codex_turn_sandbox_policy: %{
          type: "workspaceWrite",
          writableRoots: [Path.expand(workspace), Path.join(Path.expand(workspace_root), ".cache")]
        }
      )

      issue = %Issue{
        id: "issue-policy-overrides",
        identifier: "MT-99",
        title: "Validate codex policy overrides",
        description: "Check startup policy payload overrides",
        state: "In Progress",
        url: "https://example.org/issues/MT-99",
        labels: ["backend"]
      }

      assert {:ok, _result} = AppServer.run(workspace, "Fix workspace start args", issue)

      lines = File.read!(trace_file) |> String.split("\n", trim: true)

      assert Enum.any?(lines, fn line ->
               if String.starts_with?(line, "JSON:") do
                 line
                 |> String.trim_leading("JSON:")
                 |> Jason.decode!()
                 |> then(fn payload ->
                   payload["method"] == "thread/start" &&
                     get_in(payload, ["params", "approvalPolicy"]) == "on-request" &&
                     get_in(payload, ["params", "sandbox"]) == "workspace-write"
                 end)
               else
                 false
               end
             end)

      expected_turn_policy = %{
        "type" => "workspaceWrite",
        "writableRoots" => [Path.expand(workspace), Path.join(Path.expand(workspace_root), ".cache")]
      }

      assert Enum.any?(lines, fn line ->
               if String.starts_with?(line, "JSON:") do
                 line
                 |> String.trim_leading("JSON:")
                 |> Jason.decode!()
                 |> then(fn payload ->
                   payload["method"] == "turn/start" &&
                     get_in(payload, ["params", "approvalPolicy"]) == "on-request" &&
                     get_in(payload, ["params", "sandboxPolicy"]) == expected_turn_policy
                 end)
               else
                 false
               end
             end)
    after
      File.rm_rf(test_root)
    end
  end
end
