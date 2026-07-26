defmodule TrieBenchmark.MixProject do
  use Mix.Project

  def project do
    [
      app: :trie_benchmark,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {TrieBenchmark, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:benchee, ">= 0.0.0"},
      {:trie_hard, "~> 0.2"},
      {:retrieval, "~> 0.9"},
      {:trie, git: "https://github.com/dimitarvp/trie", tag: "master"}
    ]
  end
end
