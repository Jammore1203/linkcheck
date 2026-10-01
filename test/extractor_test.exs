defmodule Linkcheck.ExtractorTest do
  use ExUnit.Case, async: true
  alias Linkcheck.Extractor

  defp urls(md), do: md |> Extractor.extract() |> Enum.map(& &1.url)

  test "inline links and images" do
    md = "See [the docs](https://example.com/docs) and ![logo](img/logo.png)."
    assert urls(md) == ["https://example.com/docs", "img/logo.png"]
  end

  test "link titles and angle brackets are stripped" do
    assert urls(~s{[a](https://a.com "Title")}) == ["https://a.com"]
    assert urls("[a](<docs/my file.md>)") == []
    assert urls("[a](<docs/file.md>)") == ["docs/file.md"]
  end

  test "brackets inside link text" do
    assert urls("[see [1]](https://a.com/ref)") == ["https://a.com/ref"]
  end

  test "autolinks and reference definitions" do
    md = """
    Visit <https://elixir-lang.org>.

    [guide]: https://hexdocs.pm/elixir "Guide"
      [local]: ./CONTRIBUTING.md
    """

    assert urls(md) == [
             "https://elixir-lang.org",
             "https://hexdocs.pm/elixir",
             "./CONTRIBUTING.md"
           ]
  end

  test "line numbers" do
    md = "first\n\n[x](https://x.com)\n"
    assert [%{url: "https://x.com", line: 3}] = Extractor.extract(md)
  end

  test "ignores fenced code blocks and inline code" do
    md = """
    ```bash
    curl https://example.com/[not](a-link)
    ```
    Use `[fake](https://fake.example)` like this, but [real](https://real.example).
    ~~~
    [also fake](nope.md)
    ~~~
    """

    assert urls(md) == ["https://real.example"]
  end

  test "classify" do
    assert Extractor.classify("https://a.com") == :remote
    assert Extractor.classify("HTTP://A.COM") == :remote
    assert Extractor.classify("docs/a.md") == :local
    assert Extractor.classify("../a.md#section") == :local
    assert Extractor.classify("#section") == :skip
    assert Extractor.classify("mailto:me@example.com") == :skip
  end
end
