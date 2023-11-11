defmodule BencheeAsync.MixProject do
  use Mix.Project

  @prerelease System.get_env("PRERELEASE_VERSION")
  @version_suffix if(@prerelease, do: "-#{@prerelease}", else: "")
  def project do
    [
      app: :benchee_async,
      version: "0.1.0#{@version_suffix}",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      preferred_cli_env: [
        "test.watch": :test,
        "test.format": :test,
        "test.compile": :test
      ],
      package: package()
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
      {:benchee, "~> 1.0", only: [:dev, :test]},
      {:mix_test_watch, "~> 1.0", only: [:dev, :test]},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      "test.compile": ["compile --warnings-as-errors"],
      "test.format": ["format --check-formatted"],
      "test.build": ["hex.build"]
    ]
  end

  defp package() do
    [
      description: "Benchee Async plugin for measuring multi-process performance",
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/Ziinc/benchee_async"}
    ]
  end
end
