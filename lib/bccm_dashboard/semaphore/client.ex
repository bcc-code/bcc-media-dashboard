defmodule BccmDashboard.Semaphore.Client do
  @moduledoc """
  Thin HTTP client for the Semaphore CI v1alpha API.

  The token and organization slug come from application config; see
  `config/runtime.exs`. All functions return `{:ok, value}` / `{:error, reason}`.
  """

  @default_base_url "https://%{org}.semaphoreci.com/api/v1alpha"

  @type project :: %{id: String.t(), name: String.t()}
  @type pipeline :: %{state: String.t(), result: String.t() | nil, created_at: integer() | nil}

  @spec list_projects(keyword()) :: {:ok, [project()]} | {:error, term()}
  def list_projects(opts \\ []) do
    with {:ok, body} <- request(:get, "/projects", opts),
         {:ok, projects} <- ensure_list(body) do
      {:ok, Enum.map(projects, &to_project/1)}
    end
  end

  @spec list_pipelines(String.t(), keyword()) :: {:ok, [pipeline()]} | {:error, term()}
  def list_pipelines(project_id, opts \\ []) when is_binary(project_id) do
    created_after = Keyword.get(opts, :created_after)

    params =
      [project_id: project_id]
      |> then(fn p -> if created_after, do: [{:created_after, created_after} | p], else: p end)

    with {:ok, body} <- request(:get, "/pipelines", Keyword.put(opts, :params, params)),
         {:ok, pipelines} <- ensure_list(body) do
      {:ok, Enum.map(pipelines, &to_pipeline/1)}
    end
  end

  # Semaphore sometimes serves JSON with a content-type Req doesn't auto-decode,
  # leaving us with a raw string. Decode lazily here so the rest of the client
  # only has to deal with structured data.
  defp ensure_list(list) when is_list(list), do: {:ok, list}

  defp ensure_list(binary) when is_binary(binary) do
    case Jason.decode(binary) do
      {:ok, list} when is_list(list) -> {:ok, list}
      {:ok, other} -> {:error, {:unexpected_body, other}}
      {:error, reason} -> {:error, {:json_decode_failed, reason}}
    end
  end

  defp ensure_list(other), do: {:error, {:unexpected_body, other}}

  defp request(method, path, opts) do
    config = config()
    token = Keyword.get(opts, :token, config.token)
    base_url = Keyword.get(opts, :base_url, config.base_url)
    params = Keyword.get(opts, :params, [])

    cond do
      is_nil(token) or token == "" ->
        {:error, :missing_token}

      is_nil(base_url) or base_url == "" ->
        {:error, :missing_base_url}

      true ->
        req_opts =
          [
            method: method,
            url: base_url <> path,
            headers: [{"authorization", "Token " <> token}],
            params: params,
            receive_timeout: 30_000
          ]
          |> Keyword.merge(Keyword.get(opts, :req_options, []))

        case Req.request(req_opts) do
          {:ok, %Req.Response{status: 200, body: body}} -> {:ok, body}
          {:ok, %Req.Response{status: status, body: body}} -> {:error, {:http, status, body}}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp to_project(%{"metadata" => %{"id" => id, "name" => name}}),
    do: %{id: id, name: name}

  defp to_project(other), do: %{id: nil, name: inspect(other)}

  defp to_pipeline(map) when is_map(map) do
    %{
      state: Map.get(map, "state"),
      result: Map.get(map, "result"),
      created_at: get_in(map, ["created_at", "seconds"])
    }
  end

  defp config do
    cfg = Application.get_env(:bccm_dashboard, __MODULE__, [])
    org = Keyword.get(cfg, :org, "bccmedia")

    %{
      token: Keyword.get(cfg, :token),
      base_url: Keyword.get(cfg, :base_url, String.replace(@default_base_url, "%{org}", org))
    }
  end
end
