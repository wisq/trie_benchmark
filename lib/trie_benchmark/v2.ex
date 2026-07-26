defmodule TrieBenchmark.V2 do
  alias TrieBenchmark, as: TB

  def run(commands) do
    IO.puts("\n**** Running V2 with #{Enum.count(commands)} possible commands ****\n")

    query_funcs = build_all_queries(commands)
    random_input = generate_random_input(800, 200, commands)
    sanity_check(random_input, query_funcs)

    Benchee.run(
      query_funcs
      |> Map.new(fn {key, fun} ->
        {key, fn -> random_input |> Enum.each(fun) end}
      end),
      time: 10,
      memory_time: 2
    )
  end

  defp build_all_queries(command_list) do
    trie_hard = build_trie_hard(command_list)
    retrieval = build_retrieval(command_list)
    dimi_trie = build_dimi_trie(command_list)
    using_ets = build_using_ets(command_list)

    %{
      triehard1: &search_trie_hard_get_then_auto(trie_hard, &1),
      triehard2: &search_trie_hard_get_then_count_then_auto(trie_hard, &1),
      retrieval: &search_retrieval(retrieval, &1),
      dimi_trie: &search_dimi_trie(dimi_trie, &1),
      using_ets: &search_using_ets(using_ets, &1)
    }
  end

  defp generate_random_input(from_commands, from_dict, commands) do
    [
      commands: {fn -> TB.words_from_commands(commands) end, from_commands},
      dict: {&TB.words_from_dict/0, from_dict}
    ]
    |> Enum.flat_map(fn {key, {fun, count}} ->
      {t, v} =
        :timer.tc(fn ->
          fun.()
          |> TB.partial_words()
          |> Enum.take(count)
        end)

      ^count = Enum.count(v)
      IO.puts("Generated #{count} words from #{key} in #{t} µs.")
      v
    end)
    |> Enum.shuffle()
  end

  defp build_trie_hard(words) do
    trie_hard = TrieHard.new()
    words |> Enum.each(&TrieHard.insert(trie_hard, &1, true))
    trie_hard
  end

  defp build_using_ets(words) do
    ets = :ets.new(:trie_benchmark, [:ordered_set])

    words
    |> Enum.map(fn c -> {c, true} end)
    |> then(&:ets.insert(ets, &1))

    ets
  end

  defp build_retrieval(words), do: Retrieval.new(words)
  defp build_dimi_trie(words), do: Trie.put_words(words)

  defp sanity_check(random_input, checks) do
    random_input
    |> Enum.each(fn word ->
      results =
        checks
        |> Map.new(fn {key, fun} ->
          {key, fun.(word)}
        end)

      case Map.values(results) |> Enum.uniq() do
        [_] -> :ok
        [_, _ | _] -> raise "Mismatch looking up #{inspect(word)}: #{inspect(results)}"
      end
    end)
  end

  defp search_trie_hard_get_then_auto(trie, input) do
    case TrieHard.get(trie, input) do
      {:ok, true} ->
        {:ok, input}

      {:not_found, _} ->
        case TrieHard.auto_complete(trie, input, 2) do
          {:ok, []} -> {:error, :not_found}
          {:ok, [match]} -> {:ok, match}
          {:ok, [_, _ | _]} -> {:error, :ambiguous}
        end
    end
  end

  defp search_trie_hard_get_then_count_then_auto(trie, input) do
    case TrieHard.get(trie, input) do
      {:ok, true} ->
        {:ok, input}

      {:not_found, _} ->
        case TrieHard.count_prefix(trie, input) do
          {:ok, 0} ->
            {:error, :not_found}

          {:ok, 1} ->
            {:ok, [match]} = TrieHard.auto_complete(trie, input, 2)
            {:ok, match}

          {:ok, n} when n > 1 ->
            {:error, :ambiguous}
        end
    end
  end

  defp search_retrieval(trie, input) do
    case Retrieval.contains?(trie, input) do
      true ->
        {:ok, input}

      false ->
        case Retrieval.prefix(trie, input) do
          [] -> {:error, :not_found}
          [match] -> {:ok, match}
          [_, _ | _] -> {:error, :ambiguous}
        end
    end
  end

  defp search_dimi_trie(trie, input) do
    case Trie.search(trie, input) do
      [] ->
        {:error, :not_found}

      [match] ->
        {:ok, match}

      [_, _ | _] = list ->
        case input in list do
          true -> {:ok, input}
          false -> {:error, :ambiguous}
        end
    end
  end

  defp search_using_ets(ets, input) do
    # Unlike the others, this extra first check is mandatory,
    # since `:ets.next` would actually skip over our exact match.
    case :ets.member(ets, input) do
      true -> {:ok, input}
      false -> ets_partial_match(ets, input)
    end
  end

  defp ets_partial_match(ets, input) do
    case :ets.next(ets, input) do
      ^input <> _ = match ->
        # Got a match, check if the next is also a match.
        case :ets.next(ets, match) do
          ^input <> _ -> {:error, :ambiguous}
          _ -> {:ok, match}
        end

      _ ->
        {:error, :not_found}
    end
  end
end
