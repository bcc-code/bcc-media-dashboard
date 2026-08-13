defmodule BccmDashboard.BuildInfo do
  @moduledoc """
  Identifies the build the dashboard is running, so what's on the wall can be
  traced back to a commit.

  The sha is baked in at compile time because a release carries no `.git`
  directory: CI passes it as the `GIT_SHA` build arg (see `Dockerfile`), and
  local builds fall back to asking git directly. When neither is available —
  e.g. a source tarball built without the env var — the sha is `nil` and the
  UI simply omits it.
  """

  # Recompile when HEAD (or the branch ref it points at) moves, so a long-lived
  # dev server doesn't keep reporting the sha it was first compiled at.
  head_path = ".git/HEAD"

  if File.exists?(head_path) do
    @external_resource head_path
  end

  with {:ok, "ref: " <> ref} <- File.read(head_path),
       ref_path = Path.join(".git", String.trim(ref)),
       true <- File.exists?(ref_path) do
    @external_resource ref_path
  end

  @sha (case System.get_env("GIT_SHA") do
          sha when is_binary(sha) and sha != "" ->
            String.trim(sha)

          _ ->
            try do
              case System.cmd("git", ["rev-parse", "HEAD"], stderr_to_stdout: true) do
                {out, 0} -> String.trim(out)
                _ -> nil
              end
            rescue
              # git isn't installed, or there's no repository here.
              ErlangError -> nil
            end
        end)

  @doc """
  The full commit sha the running build was compiled from, or `nil` if unknown.
  """
  @spec sha() :: String.t() | nil
  def sha, do: @sha

  @doc """
  The abbreviated commit sha, or `nil` if unknown.
  """
  @spec short_sha() :: String.t() | nil
  def short_sha, do: if(@sha, do: String.slice(@sha, 0, 7))
end
