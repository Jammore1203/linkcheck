defmodule Linkcheck.Extractor do
  @moduledoc """
  Pulls links out of Markdown, with line numbers.

  Finds inline links and images (`[text](url)`, `![alt](url)`), autolinks
  (`<https://...>`) and reference definitions (`[id]: url`). Anything
  inside fenced code blocks or inline code spans is ignored, since
  example URLs there aren't meant to resolve.
  """

  @inline ~r/!?\[(?:[^\[\]]|\[[^\]]*\])*\]\(\s*<?([^)\s>]+)>?(?:\s+["'(][^)]*["')])?\s*\)/
  @autolink ~r/<(https?:\/\/[^>\s]+)>/
  @reference ~r/^\s{0,3}\[[^\]]+\]:\s*<?(\S+?)>?(?:\s+["'(].*)?\s*$/
  @fence ~r/^\s{0,3}(```|~~~)/

  @type link :: %{url: String.t(), line: pos_integer()}

  @spec extract(String.t()) :: [link]
  def extract(markdown) do
    markdown
    |> String.split(["\r\n", "\n"])
    |> Enum.with_index(1)
    |> drop_fenced_blocks()
    |> Enum.flat_map(fn {line, n} ->
      line = strip_inline_code(line)

      [@inline, @autolink, @reference]
      |> Enum.flat_map(&Regex.scan(&1, line, capture: :all_but_first))
      |> Enum.map(fn [url] -> %{url: url, line: n} end)
    end)
    |> Enum.uniq()
  end

  @doc """
  What kind of link this is: `:remote` (http/https), `:local` (a path
  relative to the Markdown file) or `:skip` (anchors, mailto:, etc).
  """
  @spec classify(String.t()) :: :remote | :local | :skip
  def classify(url) do
    cond do
      String.match?(url, ~r/^https?:\/\//i) -> :remote
      String.starts_with?(url, "#") -> :skip
      String.match?(url, ~r/^[a-z][a-z0-9+.-]*:/i) -> :skip
      true -> :local
    end
  end

  defp drop_fenced_blocks(lines) do
    {kept, _in_fence} =
      Enum.reduce(lines, {[], false}, fn {text, _n} = line, {acc, in_fence} ->
        cond do
          Regex.match?(@fence, text) -> {acc, not in_fence}
          in_fence -> {acc, true}
          true -> {[line | acc], false}
        end
      end)

    Enum.reverse(kept)
  end

  defp strip_inline_code(line), do: Regex.replace(~r/`+[^`]*`+/, line, "")
end
