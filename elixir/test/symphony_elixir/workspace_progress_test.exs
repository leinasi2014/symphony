defmodule SymphonyElixir.WorkspaceProgressTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.WorkspaceProgress

  test "capture uses git fingerprint data for git workspaces" do
    root = Path.join(System.tmp_dir!(), "workspace-progress-git-#{System.unique_integer([:positive])}")

    try do
      File.mkdir_p!(root)
      File.write!(Path.join(root, "tracked.txt"), "one\ntwo\n")
      System.cmd("git", ["-C", root, "init", "-b", "main"])
      System.cmd("git", ["-C", root, "config", "user.name", "Test User"])
      System.cmd("git", ["-C", root, "config", "user.email", "test@example.com"])
      System.cmd("git", ["-C", root, "add", "tracked.txt"])
      System.cmd("git", ["-C", root, "commit", "-m", "initial"])

      File.write!(Path.join(root, "tracked.txt"), "one\ntwo\nthree\n")
      File.write!(Path.join(root, "new.txt"), "new file\n")

      assert {:ok, fingerprint} = WorkspaceProgress.capture(root)
      assert fingerprint.kind == :git
      assert fingerprint.changed_file_count == 2
      assert fingerprint.added_lines >= 1
      assert is_binary(fingerprint.changed_files_hash)
      assert byte_size(fingerprint.changed_files_hash) == 64
      assert is_binary(fingerprint.changed_content_hash)
      assert byte_size(fingerprint.changed_content_hash) == 64
    after
      File.rm_rf(root)
    end
  end

  test "git fingerprint changes when an untracked file content changes without path changes" do
    root = Path.join(System.tmp_dir!(), "workspace-progress-content-#{System.unique_integer([:positive])}")

    try do
      File.mkdir_p!(root)
      File.write!(Path.join(root, "tracked.txt"), "one\ntwo\n")
      System.cmd("git", ["-C", root, "init", "-b", "main"])
      System.cmd("git", ["-C", root, "config", "user.name", "Test User"])
      System.cmd("git", ["-C", root, "config", "user.email", "test@example.com"])
      System.cmd("git", ["-C", root, "add", "tracked.txt"])
      System.cmd("git", ["-C", root, "commit", "-m", "initial"])

      File.write!(Path.join(root, "new.txt"), "one line\n")
      assert {:ok, fingerprint_a} = WorkspaceProgress.capture(root)

      File.write!(Path.join(root, "new.txt"), "one line\ntwo line\nthree line\n")
      assert {:ok, fingerprint_b} = WorkspaceProgress.capture(root)

      assert fingerprint_a.changed_files_hash == fingerprint_b.changed_files_hash
      assert fingerprint_a.changed_content_hash != fingerprint_b.changed_content_hash
    after
      File.rm_rf(root)
    end
  end

  test "capture falls back to filesystem fingerprint for non-git workspaces" do
    root = Path.join(System.tmp_dir!(), "workspace-progress-fs-#{System.unique_integer([:positive])}")

    try do
      File.mkdir_p!(Path.join(root, "nested"))
      File.write!(Path.join(root, "a.txt"), "alpha")
      File.write!(Path.join(root, "nested/b.txt"), "beta")

      assert {:ok, fingerprint} = WorkspaceProgress.capture(root)
      assert fingerprint.kind == :filesystem
      assert fingerprint.file_count == 2
      assert fingerprint.total_size_bytes == 9
      assert is_binary(fingerprint.content_hash)
      assert byte_size(fingerprint.content_hash) == 64
    after
      File.rm_rf(root)
    end
  end

  test "apply_fingerprint tracks baseline changes and disabled no-progress counting" do
    entry = %{
      mode: :probe,
      no_progress_turns: 0,
      last_progress_fingerprint: nil
    }

    fingerprint_a = %{
      kind: :git,
      changed_file_count: 1,
      added_lines: 2,
      removed_lines: 0,
      changed_files_hash: String.duplicate("a", 64)
    }

    fingerprint_b = %{
      kind: :git,
      changed_file_count: 2,
      added_lines: 4,
      removed_lines: 1,
      changed_files_hash: String.duplicate("b", 64)
    }

    baseline = WorkspaceProgress.apply_fingerprint(entry, fingerprint_a)
    assert baseline.mode == :probe
    assert baseline.no_progress_turns == 0
    assert baseline.last_progress_fingerprint == fingerprint_a

    unchanged = WorkspaceProgress.apply_fingerprint(baseline, fingerprint_a)
    assert unchanged.no_progress_turns == 1

    progressed = WorkspaceProgress.apply_fingerprint(unchanged, fingerprint_b)
    assert progressed.mode == :default
    assert progressed.no_progress_turns == 0
    assert progressed.last_progress_fingerprint == fingerprint_b

    disabled = WorkspaceProgress.apply_fingerprint(progressed, fingerprint_b, no_progress_enabled: false)
    assert disabled.no_progress_turns == 0
  end
end
