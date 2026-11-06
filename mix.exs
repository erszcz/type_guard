defmodule TypeGuard.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :type_guard,
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "TypeGuard",
      description: "Runtime checks of values against their plain Elixir typespecs.",
      docs: docs()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:ecto, "~> 3.10", optional: true},
      {:polymorphic_embed, "~> 5.0", optional: true},
      {:open_api_spex, "~> 3.21", optional: true},
      {:uuidv7, "~> 1.0", only: :test},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: [
        "README.md",
        "guides/conventions.md",
        "guides/remote_types.md",
        "guides/code_reloading.md",
        "guides/ecto.md",
        "guides/open_api_spex.md"
      ],
      groups_for_extras: [Guides: ~r{guides/}],
      groups_for_modules: [
        Integrations: [TypeGuard.Ecto, TypeGuard.PolymorphicEmbed, TypeGuard.OpenApiSpex]
      ]
    ]
  end
end
