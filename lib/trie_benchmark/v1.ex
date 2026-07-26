defmodule TrieBenchmark.V1 do
  alias TrieBenchmark, as: TB

  def run(commands, opts) do
    {max_matches, opts} = Keyword.pop(opts, :max_matches, :all)
    {filter_input?, opts} = Keyword.pop(opts, :filter_input, true)
    unless Enum.empty?(opts), do: raise("Unknown options: #{inspect(opts)}")

    IO.puts([
      "\n",
      "**** Running V1 with #{Enum.count(commands)} possible commands,",
      " #{max_matches} possible matches",
      if max_matches == :all do
        ""
      else
        ", input fitering #{if filter_input?, do: "enabled", else: "disabled"}"
      end,
      " ****\n"
    ])

    max_input_matches = if filter_input?, do: max_matches, else: :all
    query_funcs = build_all_queries(commands, max_matches)
    random_input = generate_random_input(800, 200, commands, max_input_matches)

    max_ambiguous = if !filter_input?, do: max_matches, else: :all
    sanity_check(random_input, query_funcs, max_ambiguous)

    Benchee.run(
      query_funcs
      |> Map.new(fn {key, fun} ->
        {key, fn -> random_input |> Enum.each(fun) end}
      end),
      time: 10,
      memory_time: 2
    )
  end

  defp build_all_queries(command_list, max_matches) do
    trie_hard = build_trie_hard(command_list)
    retrieval = build_retrieval(command_list)
    dimi_trie = build_dimi_trie(command_list)
    using_ets = build_using_ets(command_list)

    max_matches =
      case max_matches do
        :all -> Enum.count(command_list)
        n when is_integer(n) -> n
      end

    %{
      trie_hard: &search_trie_hard(trie_hard, &1, max_matches),
      retrieval: &search_retrieval(retrieval, &1),
      dimi_trie: &search_dimi_trie(dimi_trie, &1),
      using_ets: &search_using_ets(using_ets, &1, max_matches)
    }
  end

  defp generate_random_input(from_commands, from_dict, commands, max_matches) do
    [
      commands: {fn -> TB.words_from_commands(commands) end, from_commands},
      dict: {&TB.words_from_dict/0, from_dict}
    ]
    |> Enum.flat_map(fn {key, {fun, count}} ->
      {t, v} =
        :timer.tc(fn ->
          fun.()
          |> partial_words(commands, max_matches)
          |> Enum.take(count)
        end)

      ^count = Enum.count(v)
      IO.puts("Generated #{count} words from #{key} in #{t} µs.")
      v
    end)
    |> Enum.shuffle()
  end

  defp partial_words(words, _, :all), do: TB.partial_words(words)

  defp partial_words(words, commands, max_matches) do
    words
    |> Stream.map(fn word ->
      len = String.length(word)

      case shortest_allowed_prefix(word, len, commands, max_matches) do
        :error -> nil
        min_len -> String.slice(word, 0, Enum.random(min_len..len))
      end
    end)
    |> Stream.reject(&is_nil/1)
  end

  defp shortest_allowed_prefix(_, 0, _, _), do: :error

  defp shortest_allowed_prefix(word, len, commands, max_matches) do
    word = String.slice(word, 0, len)
    count = commands |> Enum.count(&String.starts_with?(&1, word))

    if count > max_matches do
      :error
    else
      case shortest_allowed_prefix(word, len - 1, commands, max_matches) do
        :error -> len
        n -> n
      end
    end
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

  defp sanity_check(random_input, checks, max_ambiguous) do
    random_input
    |> Enum.each(fn word ->
      results =
        checks
        |> Map.new(fn {key, fun} ->
          {key, fun.(word) |> sanity_check_ambiguous(max_ambiguous)}
        end)

      case Map.values(results) |> Enum.uniq() do
        [_] -> :ok
        [_, _ | _] -> raise "Mismatch looking up #{inspect(word)}: #{inspect(results)}"
      end
    end)
  end

  defp sanity_check_ambiguous({:ok, _} = rval, _), do: rval
  defp sanity_check_ambiguous({:error, _} = rval, _), do: rval

  defp sanity_check_ambiguous({:error, :ambiguous, list}, :all) do
    {:error, :ambiguous, Enum.sort(list)}
  end

  defp sanity_check_ambiguous({:error, :ambiguous, list}, max) when is_integer(max) do
    {:error, :ambiguous, Enum.count(list) |> min(max)}
  end

  defp search_trie_hard(trie, input, max_matches) do
    case TrieHard.auto_complete(trie, input, max_matches) do
      {:ok, []} -> {:error, :not_found}
      {:ok, [match]} -> {:ok, match}
      {:ok, [_, _ | _] = list} -> check_exact_match(list, input)
    end
  end

  defp search_retrieval(trie, input) do
    case Retrieval.prefix(trie, input) do
      [] -> {:error, :not_found}
      [match] -> {:ok, match}
      [_, _ | _] = list -> check_exact_match(list, input)
    end
  end

  defp search_dimi_trie(trie, input) do
    case Trie.search(trie, input) do
      [] -> {:error, :not_found}
      [match] -> {:ok, match}
      [_, _ | _] = list -> check_exact_match(list, input)
    end
  end

  defp search_using_ets(ets, input, max_matches) do
    # Unlike the others, this extra first check is mandatory,
    # since `:ets.next` would actually skip over our exact match.
    case :ets.member(ets, input) do
      true ->
        {:ok, input}

      false ->
        case ets_all_matches(ets, input, input, max_matches) do
          [] -> {:error, :not_found}
          [match] -> {:ok, match}
          # Unlike the others, we don't need to check_exact_match/2 here.
          [_, _ | _] = list -> {:error, :ambiguous, list}
        end
    end
  end

  defp ets_all_matches(_ets, _input, _pos, 0), do: []

  defp ets_all_matches(ets, input, pos, max) do
    case :ets.next(ets, pos) do
      ^input <> _ = match -> [match | ets_all_matches(ets, input, match, max - 1)]
      _ -> []
    end
  end

  defp check_exact_match(list, input) do
    case input in list do
      true -> {:ok, input}
      false -> {:error, :ambiguous, list}
    end
  end
end
