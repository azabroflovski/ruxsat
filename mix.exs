defmodule Ruxsat.MixProject do
  use Mix.Project

  @version "0.2.0"
  @source_url "https://github.com/azabroflovski/ruxsat"

  def project do
    [
      app: :ruxsat,
      version: @version,
      elixir: "~> 1.15",
      description: "Small, explicit authorization for Elixir.",
      source_url: @source_url,
      package: package(),
      docs: docs(),
      deps: deps()
    ]
  end

  def application do
    []
  end

  defp deps do
    [
      {:ex_doc, "~> 0.40", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib .formatter.exs mix.exs README.md CHANGELOG.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md"],
      source_ref: "v#{@version}"
    ]
  end
end
