defmodule Linkcheck.CLI do
  @moduledoc false

  @usage """
  usage: linkcheck [options] [PATH...]

  Checks every link in the Markdown files under PATH (default: .).
  Exits with status 1 if any link is broken.

    -t, --timeout MS       per-request timeout (default 10000)
    -c, --concurrency N    parallel requests (default 16)
        --offline          only check links to local files
    -v, --verbose          also list links that are fine
    -h, --help             show this help
  """

  def main(argv) do
    {code, output} = run(argv)
    IO.write(output)
    System.halt(code)
  end

  @doc """
  Runs the CLI and returns `{exit_code, output}` instead of exiting, so
  it can be tested. `extra` is merged into the checker options.
  """
  def run(argv, extra \\ []) do
    {opts, paths, invalid} =
      OptionParser.parse(argv,
        strict: [
          timeout: :integer,
          concurrency: :integer,
          offline: :boolean,
          verbose: :boolean,
          help: :boolean
        ],
        aliases: [t: :timeout, c: :concurrency, v: :verbose, h: :help]
      )

    cond do
      opts[:help] ->
        {0, @usage}

      invalid != [] ->
        {2, "linkcheck: bad option #{elem(hd(invalid), 0)}\n\n" <> @usage}

      true ->
        paths = if paths == [], do: ["."], else: paths

        case Enum.reject(paths, &File.exists?/1) do
          [] -> check(paths, Keyword.merge(opts, extra))
          missing -> {2, "linkcheck: no such file or directory: #{Enum.join(missing, ", ")}\n"}
        end
    end
  end

  defp check(paths, opts) do
    files = Linkcheck.markdown_files(paths)
    results = Linkcheck.run(files, opts)

    broken = Enum.filter(results, &match?({:broken, _}, &1.outcome))
    warnings = Enum.filter(results, &match?({:warn, _}, &1.outcome))
    shown = if opts[:verbose], do: results, else: broken ++ warnings

    lines =
      shown
      |> Enum.sort_by(&{&1.file, &1.line})
      |> Enum.map(&format/1)

    unique = results |> Enum.map(& &1.url) |> Enum.uniq() |> length()

    summary =
      "#{length(results)} links (#{unique} unique) in #{length(files)} files: " <>
        "#{length(broken)} broken, #{length(warnings)} warnings\n"

    output = Enum.join(lines) <> if(lines == [], do: "", else: "\n") <> summary
    {if(broken == [], do: 0, else: 1), output}
  end

  defp format(%{file: f, line: l, url: u, outcome: outcome}) do
    {tag, detail} =
      case outcome do
        {:ok, status} -> {"ok", Integer.to_string(status)}
        {:warn, why} -> {"WARN", why}
        {:broken, why} -> {"BROKEN", why}
      end

    "#{String.pad_trailing(tag, 7)}#{f}:#{l}  #{u}  (#{detail})\n"
  end
end
