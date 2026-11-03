defmodule Catalog.MixProject do
  use Mix.Project

  def project do
    [
      app: :catalog,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application, do: [extra_applications: [:logger]]

  defp deps do
    [
      {:type_guard, path: "../.."},
      {:ecto, "~> 3.10"},
      {:polymorphic_embed, "~> 5.0"},
      {:uuidv7, "~> 1.0"}
    ]
  end
end
