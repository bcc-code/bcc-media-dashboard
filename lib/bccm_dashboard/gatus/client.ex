defmodule BccmDashboard.Gatus.Client do
  @moduledoc """
  Thin HTTP client for the [Gatus](https://gatus.io) status API.

  Gatus exposes `/api/v1/endpoints/statuses`, returning every monitored
  endpoint plus its recent check results in a single call. Token auth is
  optional — public Gatus deployments don't require it.

  Config comes from `config/runtime.exs`. All functions return
  `{:ok, value}` / `{:error, reason}`.
  """

  @type result :: %{
          success: boolean(),
          timestamp: String.t() | nil,
          duration: integer() | nil,
          errors: [String.t()]
        }

  @type endpoint :: %{
          key: String.t() | nil,
          name: String.t() | nil,
          group: String.t() | nil,
          results: [result()]
        }

  @spec list_endpoint_statuses(keyword()) :: {:ok, [endpoint()]} | {:error, term()}
  def list_endpoint_statuses(opts \\ []) do
    page_size = Keyword.get(opts, :page_size, 50)
    params = [page: 1, pageSize: page_size]

    with {:ok, body} <-
           request(:get, "/api/v1/endpoints/statuses", Keyword.put(opts, :params, params)),
         {:ok, list} <- ensure_list(body) do
      {:ok, Enum.map(list, &to_endpoint/1)}
    end
  end

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
    base_url = Keyword.get(opts, :base_url, config.base_url)
    token = Keyword.get(opts, :token, config.token)
    params = Keyword.get(opts, :params, [])

    if is_nil(base_url) or base_url == "" do
      {:error, :missing_base_url}
    else
      req_opts =
        [
          method: method,
          url: String.trim_trailing(base_url, "/") <> path,
          headers: auth_headers(token),
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

  defp auth_headers(token) when is_binary(token) and token != "",
    do: [{"authorization", "Bearer " <> token}]

  defp auth_headers(_), do: []

  defp to_endpoint(map) when is_map(map) do
    %{
      key: Map.get(map, "key"),
      name: Map.get(map, "name"),
      group: Map.get(map, "group"),
      results: map |> Map.get("results", []) |> Enum.map(&to_result/1)
    }
  end

  defp to_endpoint(_), do: %{key: nil, name: "?", group: nil, results: []}

  defp to_result(map) when is_map(map) do
    %{
      success: Map.get(map, "success", false),
      timestamp: Map.get(map, "timestamp"),
      duration: Map.get(map, "duration"),
      errors: Map.get(map, "errors") || []
    }
  end

  defp to_result(_), do: %{success: false, timestamp: nil, duration: nil, errors: []}

  defp config do
    cfg = Application.get_env(:bccm_dashboard, __MODULE__, [])

    %{
      base_url: Keyword.get(cfg, :base_url),
      token: Keyword.get(cfg, :token)
    }
  end
end
