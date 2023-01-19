defmodule Punt.MixProject do
  use Mix.Project

  @url "https://github.com/maartenvanvliet/punt"
  def project do
    [
      app: :punt,
      version: "0.1.1",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Parse data structures",
      source_url: @url,
      homepage_url: @url,
      package: [
        maintainers: ["Maarten van Vliet"],
        licenses: ["MIT"],
        links: %{"GitHub" => @url},
        files: ~w(LICENSE README.md lib mix.exs .formatter.exs)
      ],
      docs: [
        main: "Punt",
        source_url: @url,
        canonical: "http://hexdocs.pm/punt"
      ]
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
      {:stream_data, "~> 0.5.0"},
      {:ex_doc, "~> 0.29", only: [:dev, :test]}
    ]
  end
end
