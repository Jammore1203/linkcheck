defmodule LinkcheckTest do
  use ExUnit.Case, async: true
  alias Linkcheck.{Checker, CLI}

  # A pretend internet.
  defp fetcher(url, _timeout) do
    case url do
      "https://ok.example" <> _ ->
        {:ok, 200}

      "https://redirect.example" ->
        {:ok, 301}

      "https://gone.example" ->
        {:ok, 404}

      "https://busy.example" ->
        {:ok, 429}

      "https://nodns.example" ->
        {:error, {:failed_connect, [{:to_address, {~c"x", 443}}, {:inet, [:inet], :nxdomain}]}}

      "https://slow.example" ->
        Process.sleep(:infinity)
    end
  end

  setup do
    dir = Path.join(System.tmp_dir!(), "linkcheck-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(dir, "docs"))
    File.write!(Path.join(dir, "docs/setup.md"), "# Setup\n")
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir}
  end

  test "interprets statuses and errors" do
    results =
      Checker.check_remote(
        [
          "https://ok.example",
          "https://redirect.example",
          "https://gone.example",
          "https://busy.example",
          "https://nodns.example",
          "https://slow.example"
        ],
        fetcher: &fetcher/2,
        timeout: 50
      )

    assert results["https://ok.example"] == {:ok, 200}
    assert results["https://redirect.example"] == {:ok, 301}
    assert results["https://gone.example"] == {:broken, "404"}
    assert results["https://busy.example"] == {:warn, "429 rate limited"}
    assert results["https://nodns.example"] == {:broken, "DNS lookup failed"}
    assert results["https://slow.example"] == {:broken, "timeout"}
  end

  test "each URL is fetched once" do
    parent = self()

    counting = fn url, _ ->
      send(parent, {:fetched, url})
      {:ok, 200}
    end

    Checker.check_remote(["https://ok.example", "https://ok.example"], fetcher: counting)
    assert_received {:fetched, "https://ok.example"}
    refute_received {:fetched, _}
  end

  test "requests run concurrently" do
    sleepy = fn _, _ -> Process.sleep(200) && {:ok, 200} end
    urls = for i <- 1..10, do: "https://ok.example/#{i}"

    {micros, _} =
      :timer.tc(fn -> Checker.check_remote(urls, fetcher: sleepy, concurrency: 10) end)

    assert micros < 1_000_000
  end

  test "local links resolve relative to the markdown file", %{dir: dir} do
    md = Path.join(dir, "README.md")
    assert Checker.check_local("docs/setup.md", md) == {:ok, 200}
    assert Checker.check_local("docs/setup.md#install", md) == {:ok, 200}
    assert Checker.check_local("./docs/", md) == {:ok, 200}
    assert Checker.check_local("docs/missing.md", md) == {:broken, "missing file"}

    assert Checker.check_local("../README.md", Path.join(dir, "docs/setup.md")) ==
             {:broken, "missing file"}
  end

  test "end to end through the CLI", %{dir: dir} do
    File.write!(Path.join(dir, "README.md"), """
    # Project
    [Setup](docs/setup.md) and [old page](docs/old.md).
    Hosted at [ok](https://ok.example) (not [here](https://gone.example)).
    [Top](#project) and [email](mailto:a@b.c) are skipped.
    """)

    {code, out} = CLI.run([dir], fetcher: &fetcher/2)
    assert code == 1
    assert out =~ "README.md:2  docs/old.md  (missing file)"
    assert out =~ "README.md:3  https://gone.example  (404)"
    refute out =~ "ok.example"
    assert out =~ "4 links (4 unique) in 2 files: 2 broken, 0 warnings"
  end

  test "offline mode skips remote links", %{dir: dir} do
    File.write!(Path.join(dir, "README.md"), "[a](https://gone.example) [b](docs/setup.md)\n")
    assert {0, out} = CLI.run(["--offline", dir], fetcher: &fetcher/2)
    assert out =~ "1 links (1 unique)"
  end

  test "bad arguments" do
    assert {2, _} = CLI.run(["--bogus"])
    assert {2, out} = CLI.run(["/no/such/path"])
    assert out =~ "no such file"
  end
end
