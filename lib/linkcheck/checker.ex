defmodule Linkcheck.Checker do
  @moduledoc """
  Checks links. Remote URLs are fetched concurrently; local links are
  resolved against the Markdown file's directory.

  The HTTP function is injectable, so everything above the network can
  be tested without one.
  """

  @type outcome :: {:ok, integer()} | {:warn, String.t()} | {:broken, String.t()}
  @type fetcher :: (String.t(), pos_integer() -> {:ok, integer()} | {:error, term()})

  @doc """
  Checks each unique URL once, in parallel. Returns `%{url => outcome}`.
  """
  @spec check_remote([String.t()], keyword()) :: %{String.t() => outcome}
  def check_remote(urls, opts \\ []) do
    fetch = Keyword.get(opts, :fetcher, &http_fetch/2)
    timeout = Keyword.get(opts, :timeout, 10_000)
    concurrency = Keyword.get(opts, :concurrency, 16)
    urls = Enum.uniq(urls)

    results =
      Task.async_stream(urls, fn url -> fetch.(url, timeout) end,
        max_concurrency: concurrency,
        timeout: timeout * 2 + 1_000,
        on_timeout: :kill_task,
        ordered: true
      )

    urls
    |> Enum.zip(results)
    |> Map.new(fn {url, result} -> {url, interpret(result)} end)
  end

  @doc false
  def interpret({:ok, {:ok, status}}) when status in 200..399, do: {:ok, status}
  def interpret({:ok, {:ok, 429}}), do: {:warn, "429 rate limited"}
  def interpret({:ok, {:ok, status}}), do: {:broken, Integer.to_string(status)}
  def interpret({:ok, {:error, reason}}), do: {:broken, describe_error(reason)}
  def interpret({:exit, :timeout}), do: {:broken, "timeout"}
  def interpret({:exit, reason}), do: {:broken, "crashed: #{inspect(reason)}"}

  @doc """
  Checks a relative link from `md_file`. Fragments and query strings are
  ignored; percent-encoding is decoded.
  """
  @spec check_local(String.t(), String.t()) :: outcome
  def check_local(url, md_file) do
    path = url |> String.split(["#", "?"]) |> hd() |> URI.decode()

    cond do
      path == "" ->
        {:ok, 200}

      File.exists?(Path.expand(path, Path.dirname(md_file))) ->
        {:ok, 200}

      true ->
        {:broken, "missing file"}
    end
  end

  @doc """
  The real fetcher: HEAD first (cheap), falling back to GET for servers
  that refuse HEAD. Redirects are followed.
  """
  @spec http_fetch(String.t(), pos_integer()) :: {:ok, integer()} | {:error, term()}
  def http_fetch(url, timeout) do
    request = {String.to_charlist(url), [{~c"user-agent", ~c"linkcheck/0.1"}]}
    http_opts = [timeout: timeout, connect_timeout: timeout, autoredirect: true, ssl: ssl_opts()]

    case :httpc.request(:head, request, http_opts, []) do
      {:ok, {{_, status, _}, _, _}} when status in [403, 404, 405, 501] ->
        get(request, http_opts)

      {:ok, {{_, status, _}, _, _}} ->
        {:ok, status}

      {:error, _} ->
        get(request, http_opts)
    end
  end

  defp get(request, http_opts) do
    case :httpc.request(:get, request, http_opts, body_format: :binary) do
      {:ok, {{_, status, _}, _, _}} -> {:ok, status}
      {:error, reason} -> {:error, reason}
    end
  end

  # Verify certificates against the OS trust store when the runtime
  # supports it (OTP 25+).
  defp ssl_opts do
    Code.ensure_loaded(:public_key)

    if function_exported?(:public_key, :cacerts_get, 0) do
      [
        verify: :verify_peer,
        cacerts: :public_key.cacerts_get(),
        depth: 4,
        customize_hostname_check: [
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        ]
      ]
    else
      [verify: :verify_none]
    end
  end

  defp describe_error({:failed_connect, [_, {_, _, reason} | _]}), do: describe_error(reason)
  defp describe_error({:failed_connect, _}), do: "connection failed"
  defp describe_error(:nxdomain), do: "DNS lookup failed"
  defp describe_error(:econnrefused), do: "connection refused"
  defp describe_error(:timeout), do: "timeout"
  defp describe_error({:tls_alert, {_, msg}}), do: "TLS error: #{msg}"
  defp describe_error(other), do: inspect(other)
end
