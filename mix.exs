defmodule KinoExRatatui.MixProject do
  use Mix.Project

  @description "Run ExRatatui apps inside Livebook via xterm.js"
  @source_url "https://github.com/mcass19/kino_ex_ratatui"
  @changelog_url @source_url <> "/blob/main/CHANGELOG.md"
  @version "0.1.0"

  def project do
    [
      app: :kino_ex_ratatui,
      description: @description,
      version: @version,
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      package: package(),
      name: "KinoExRatatui",
      homepage_url: @source_url,
      source_url: @source_url,
      docs: docs(),
      dialyzer: [
        plt_local_path: "plts",
        plt_core_path: "plts/core"
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp aliases do
    [
      "assets.install": ["cmd --cd assets npm install"],
      "assets.build": ["cmd --cd assets npm run build"]
    ]
  end

  defp deps do
    [
      {:ex_ratatui, "~> 0.8"},
      {:kino, "~> 0.13"},

      # Dev
      {:ex_doc, "~> 0.35", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => @changelog_url
      },
      keywords: ~w(kino livebook tui terminal ratatui ex_ratatui xterm),
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: [
        "README.md": [title: "Overview"],
        "CONTRIBUTING.md": [title: "Contributing"],
        "CHANGELOG.md": [title: "Changelog"]
      ],
      groups_for_modules: [
        Widgets: [
          Kino.ExRatatui,
          Kino.ExRatatui.Frame
        ]
      ]
    ]
  end
end
