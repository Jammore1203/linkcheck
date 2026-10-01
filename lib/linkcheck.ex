defmodule Linkcheck do
  @moduledoc """
  Finds every link in a set of Markdown files and checks it.
  """

  alias Linkcheck.{Checker, Extractor}

  defmodule Result do
    @moduledoc false
    defstruct [:file, :line, :url, :outcome]
  end

  @doc """
  All Markdown files under the given paths (files are taken as-is).
  Hidden directories and common dependency folders are skipped.
  """
  @spec markdown_files([String.t()]) :: [String.t()]
  def markdown_files(paths) do
    paths
    |> Enum.flat_map(fn path ->
      if File.dir?(path) do
        Path.wildcard(Path.join(path, "**/*.{md,markdown}"))
        |> Enum.reject(&String.match?(&1, ~r{(^|/)(node_modules|deps|_build|vendor)/}))
      else
        [path]
      end
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Checks every link in `files`. Options: `:fetcher`, `:timeout`,
  `:concurrency`, `:offline` (skip remote links).
  """
  @spec run([String.t()], keyword()) :: [%Result{}]
  def run(files, opts \\ []) do
    links =
      for file <- files,
          link <- Extractor.extract(File.read!(file)),
          kind = Extractor.classify(link.url),
          kind != :skip,
          not (kind == :remote and Keyword.get(opts, :offline, false)),
          do: {file, link, kind}

    remote_urls = for {_, link, :remote} <- links, do: link.url
    remote = Checker.check_remote(remote_urls, opts)

    for {file, link, kind} <- links do
      outcome =
        case kind do
          :remote -> Map.fetch!(remote, link.url)
          :local -> Checker.check_local(link.url, file)
        end

      %Result{file: file, line: link.line, url: link.url, outcome: outcome}
    end
  end
end
