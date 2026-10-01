defmodule Linkcheck.MixProject do
  use Mix.Project

  def project do
    [
      app: :linkcheck,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      escript: [main_module: Linkcheck.CLI],
      deps: []
    ]
  end

  def application do
    [extra_applications: [:logger, :inets, :ssl]]
  end
end
