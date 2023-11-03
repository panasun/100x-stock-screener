defmodule ShopeeScrape.MixProject do
  use Mix.Project

  def project do
    [
      app: :stock_screener,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:httpoison, "~> 2.0"},
      {:jason, "~> 1.4"},
      {:floki, "~> 0.34.0"},
      {:csv, "~> 3.0"},
      {:elixlsx, "~> 0.5.1"},
      {:cubdb, "~> 2.0"}
    ]
  end
end
