defmodule SymphonyElixir.WorkspaceProgress do
  @moduledoc """
  Captures deterministic workspace fingerprints and updates guardrail progress state.
  """

  @ignored_entries MapSet.new([".git", ".elixir_ls", "tmp"])

  @type fingerprint ::
          %{
            kind: :git,
            changed_file_count: non_neg_integer(),
            added_lines: non_neg_integer(),
            removed_lines: non_neg_integer(),
            changed_files_hash: String.t(),
            changed_content_hash: String.t()
          }
          | %{
              kind: :filesystem,
              file_count: non_neg_integer(),
              total_size_bytes: non_neg_integer(),
              content_hash: String.t()
            }

  @spec capture(Path.t()) :: {:ok, fingerprint()} | {:error, term()}
  def capture(workspace) when is_binary(workspace) do
    workspace = Path.expand(workspace)

    cond do
      !File.dir?(workspace) ->
        {:error, {:workspace_missing, workspace}}

      git_workspace?(workspace) ->
        capture_git_fingerprint(workspace)

      true ->
        capture_filesystem_fingerprint(workspace)
    end
  end

  @spec apply_fingerprint(map(), fingerprint(), keyword()) :: map()
  def apply_fingerprint(entry, fingerprint, opts \\ [])

  def apply_fingerprint(entry, fingerprint, opts) when is_map(entry) and is_map(fingerprint) do
    no_progress_enabled = Keyword.get(opts, :no_progress_enabled, true)
    previous = Map.get(entry, :last_progress_fingerprint)
    baseline_pending = Map.get(entry, :progress_baseline_pending, false)

    cond do
      is_nil(previous) ->
        entry
        |> Map.put(:last_progress_fingerprint, fingerprint)
        |> Map.put(:no_progress_turns, 0)
        |> Map.put(:progress_baseline_pending, false)

      baseline_pending and previous == fingerprint ->
        entry
        |> Map.put(:last_progress_fingerprint, fingerprint)
        |> Map.put(:no_progress_turns, 0)
        |> Map.put(:progress_baseline_pending, false)

      baseline_pending ->
        entry
        |> Map.put(:last_progress_fingerprint, fingerprint)
        |> Map.put(:no_progress_turns, 0)
        |> Map.put(:progress_baseline_pending, false)
        |> maybe_promote_probe_mode()

      previous == fingerprint ->
        entry
        |> Map.put(:last_progress_fingerprint, fingerprint)
        |> Map.put(:no_progress_turns, unchanged_no_progress_turns(entry, no_progress_enabled))
        |> Map.put(:progress_baseline_pending, false)

      true ->
        entry
        |> Map.put(:last_progress_fingerprint, fingerprint)
        |> Map.put(:no_progress_turns, 0)
        |> Map.put(:progress_baseline_pending, false)
        |> maybe_promote_probe_mode()
    end
  end

  def apply_fingerprint(entry, _fingerprint, _opts), do: entry

  defp unchanged_no_progress_turns(entry, true) do
    Map.get(entry, :no_progress_turns, 0) + 1
  end

  defp unchanged_no_progress_turns(_entry, false), do: 0

  defp maybe_promote_probe_mode(%{mode: :probe} = entry), do: Map.put(entry, :mode, :default)
  defp maybe_promote_probe_mode(entry), do: entry

  defp git_workspace?(workspace) do
    case System.cmd("git", ["rev-parse", "--is-inside-work-tree"], cd: workspace, stderr_to_stdout: true) do
      {"true\n", 0} -> true
      _ -> false
    end
  end

  defp capture_git_fingerprint(workspace) do
    with {:ok, changed_files} <- git_changed_files(workspace),
         {:ok, {added_lines, removed_lines}} <- git_numstat_totals(workspace) do
      changed_files =
        changed_files
        |> Enum.uniq()
        |> Enum.sort()

      {:ok,
       %{
         kind: :git,
         changed_file_count: length(changed_files),
         added_lines: added_lines,
         removed_lines: removed_lines,
         changed_files_hash: hash_strings(changed_files),
         changed_content_hash: hash_changed_files(workspace, changed_files)
       }}
    end
  end

  defp git_changed_files(workspace) do
    case System.cmd("git", ["status", "--porcelain=v1", "--untracked-files=all"], cd: workspace, stderr_to_stdout: true) do
      {output, 0} ->
        changed_files =
          output
          |> String.split("\n", trim: true)
          |> Enum.map(&parse_status_path/1)
          |> Enum.reject(&is_nil/1)

        {:ok, changed_files}

      {output, status} ->
        {:error, {:git_status_failed, status, output}}
    end
  end

  defp git_numstat_totals(workspace) do
    case System.cmd("git", ["rev-parse", "--verify", "HEAD"], cd: workspace, stderr_to_stdout: true) do
      {_output, 0} ->
        case System.cmd("git", ["diff", "--numstat", "HEAD"], cd: workspace, stderr_to_stdout: true) do
          {output, 0} -> {:ok, parse_numstat_totals(output)}
          {output, status} -> {:error, {:git_diff_failed, status, output}}
        end

      _ ->
        {:ok, {0, 0}}
    end
  end

  defp parse_status_path(line) do
    case String.split(String.slice(line, 3..-1//1) || "", " -> ", parts: 2) do
      [path] -> String.trim(path)
      [_old_path, new_path] -> String.trim(new_path)
      _ -> nil
    end
    |> case do
      "" -> nil
      path -> path
    end
  end

  defp parse_numstat_totals(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.reduce({0, 0}, fn line, {added_acc, removed_acc} ->
      case String.split(line, "\t", parts: 3) do
        [added, removed, _path] ->
          {added_acc + parse_numstat_value(added), removed_acc + parse_numstat_value(removed)}

        _ ->
          {added_acc, removed_acc}
      end
    end)
  end

  defp parse_numstat_value("-"), do: 0

  defp parse_numstat_value(value) do
    case Integer.parse(value) do
      {parsed, ""} -> parsed
      _ -> 0
    end
  end

  defp capture_filesystem_fingerprint(workspace) do
    files =
      workspace
      |> list_files_recursively()
      |> Enum.sort()

    file_metadata =
      Enum.map(files, fn relative_path ->
        full_path = Path.join(workspace, relative_path)
        {:ok, content} = File.read(full_path)
        %{path: relative_path, size: byte_size(content), hash: hash_binary(content)}
      end)

    {:ok,
     %{
       kind: :filesystem,
       file_count: length(file_metadata),
       total_size_bytes: Enum.reduce(file_metadata, 0, &(&1.size + &2)),
       content_hash:
         file_metadata
         |> Enum.map_join("\n", fn item -> "#{item.path}\t#{item.size}\t#{item.hash}" end)
         |> hash_string()
     }}
  rescue
    error in [File.Error] ->
      {:error, {:filesystem_fingerprint_failed, Exception.message(error)}}
  end

  defp list_files_recursively(root) do
    do_list_files_recursively(root, "")
  end

  defp do_list_files_recursively(root, relative_dir) do
    current_dir = if relative_dir == "", do: root, else: Path.join(root, relative_dir)

    current_dir
    |> File.ls!()
    |> Enum.flat_map(fn entry ->
      if MapSet.member?(@ignored_entries, entry) do
        []
      else
        relative_path = if relative_dir == "", do: entry, else: Path.join(relative_dir, entry)
        full_path = Path.join(root, relative_path)

        cond do
          File.dir?(full_path) -> do_list_files_recursively(root, relative_path)
          File.regular?(full_path) -> [relative_path]
          true -> []
        end
      end
    end)
  end

  defp hash_strings(strings), do: strings |> Enum.join("\n") |> hash_string()

  defp hash_changed_files(workspace, changed_files) do
    changed_files
    |> Enum.map_join("\n", fn relative_path ->
      full_path = Path.join(workspace, relative_path)

      if File.regular?(full_path) do
        {:ok, content} = File.read(full_path)
        "#{relative_path}\t#{hash_binary(content)}"
      else
        "#{relative_path}\tdeleted"
      end
    end)
    |> hash_string()
  end

  defp hash_string(value) when is_binary(value), do: hash_binary(value)

  defp hash_binary(value) do
    :sha256
    |> :crypto.hash(value)
    |> Base.encode16(case: :lower)
  end
end
