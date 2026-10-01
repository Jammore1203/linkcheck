# linkcheck

![CI](https://github.com/Jammore1203/linkcheck/actions/workflows/ci.yml/badge.svg)

Finds dead links in your Markdown. Written in Elixir, with no dependencies beyond OTP.

It checks every link in every `.md` file under a directory: web URLs are requested in parallel, and relative links to other files in the repo are checked on disk. The exit status is non-zero if anything is broken, so you can drop it into CI and stop shipping docs with 404s.

```console
$ linkcheck docs/
BROKEN docs/install.md:14  https://example.com/old-download-page  (404)
BROKEN docs/install.md:31  ../images/arch-diagram.png  (missing file)
WARN   docs/faq.md:8  https://api.github.com/repos/x/y  (429 rate limited)

57 links (41 unique) in 9 files: 2 broken, 1 warnings
```

## Usage

```
linkcheck [options] [PATH...]

  -t, --timeout MS       per-request timeout (default 10000)
  -c, --concurrency N    parallel requests (default 16)
      --offline          only check links to local files
  -v, --verbose          also list links that are fine
```

### What counts as a link

- inline links and images: `[text](url)`, `![alt](img.png)`
- autolinks: `<https://example.com>`
- reference definitions: `[id]: https://example.com`

Links inside fenced code blocks and `inline code` are ignored, since example URLs there aren't meant to resolve. Anchors (`#section`) and `mailto:` links are skipped. For local links, `#fragment` and `?query` are stripped and `%20`-style encoding is decoded before the file is looked up.

### In CI

```yaml
- run: mix escript.install github Jammore1203/linkcheck --force
- run: ~/.mix/escripts/linkcheck .
```

## Install

```bash
mix escript.install github Jammore1203/linkcheck
# or build locally
mix escript.build && ./linkcheck --help
```

## How it works

- **Concurrency.** Unique URLs go through `Task.async_stream` with a concurrency cap. A server that hangs costs one timeout, not the whole run: tasks that overrun are killed and reported as `timeout`.
- **Each URL is fetched once**, however many files link to it.
- **HEAD, then GET.** It tries `HEAD` first, which is cheap, then falls back to `GET` for servers that reject or mishandle it (403/404/405/501). Redirects are followed.
- **TLS** certificates are verified against the OS trust store on OTP 25+.
- **429** counts as a warning, not a failure, since rate limiting isn't a dead link.
- The HTTP client is **injected**, so the test suite runs a fake internet: timeouts, DNS failures, rate limits and redirects, all with no network. There's also a test that proves requests really run in parallel.
