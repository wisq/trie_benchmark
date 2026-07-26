defmodule TrieBenchmark do
  use Application

  @commands ~w{
    @@ @allhalt @allquota @assert @atrchown @atrlock @attribute @boot @break
    @cemit @channel @chat @chown @chownall @chzone @chzoneall @clist @clock
    @clone @command @config @cpattr @create @dbck @decompile @destroy @dig
    @disable @dolist @drain @dump @edit @elock @emit @enable @entrances
    @eunlock @find @firstexit @flag @force @function @grep @halt @hide @hook
    @http @ifelse @include @kick @lemit @link @list @listmotd @lock @log
    @logwipe @lset @mail @malias @mapsql @message @moniker @motd @mvattr @name
    @newpassword @notify @nscemit @nsemit @nslemit @nsoemit @nspemit @nsprompt
    @nsremit @nszemit @nuke @oemit @open @parent @password @pcreate @pemit
    @poll @poor @power @prompt @ps @purge @quota @readcache @recycle
    @rejectmotd @remit @respond @restart @retry @rwall @scan @search @select
    @set @shutdown @sitelock @skip @slave @sockset @sql @squota @stats @suggest
    @sweep @switch @teleport @trigger @ulock @undestroy @unlink @unlock
    @unrecycle @uptime @uunlock @verb @version @wait @wall @warnings @wcheck
    @whereis @wipe @wizmotd @wizwall @zemit addcom ahelp anews attrib_set brief
    buy comlist comtitle delcom desert dismiss doing drop empty enter examine
    follow get give goto help home huh_command inventory leave look news page
    pose say score semipose session teach think unfollow unimplemented_command
    use warn_on_missing whisper who with
  }

  def start(_, _) do
    run()
    {:ok, self()}
  end

  defp run do
    query_funcs = build_all_queries()
    random_input = generate_random_input(800, 200)
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

  defp build_all_queries do
    trie_hard = build_trie_hard()
    retrieval = build_retrieval()
    dimi_trie = build_dimi_trie()

    %{
      trie_hard: &search_trie_hard(trie_hard, &1),
      retrieval: &search_retrieval(retrieval, &1),
      dimi_trie: &search_dimi_trie(dimi_trie, &1)
    }
  end

  defp generate_random_input(from_commands, from_dict) do
    [
      commands: {&words_from_commands/1, from_commands},
      dict: {&words_from_dict/1, from_dict}
    ]
    |> Enum.flat_map(fn {key, {fun, count}} ->
      {t, v} = :timer.tc(fn -> fun.(count) end)
      ^count = Enum.count(v)
      IO.puts("Generated #{count} words from #{key} in #{t} µs.")
      v
    end)
    |> Enum.shuffle()
  end

  defp words_from_commands(count) do
    Stream.repeatedly(fn ->
      c = Enum.random(@commands)
      l = Enum.random(1..String.length(c))
      String.slice(c, 0, l)
    end)
    |> Stream.reject(fn
      "@" -> true
      <<"@", _>> -> true
      _ -> false
    end)
    |> Enum.take(count)
  end

  defp words_from_dict(count) do
    File.stream!("/usr/share/dict/words")
    |> Enum.shuffle()
    |> Stream.map(&:string.chomp/1)
    |> Stream.filter(&(&1 =~ ~r{^[a-z]+$}))
    |> Enum.take(count)
  end

  defp build_trie_hard do
    trie_hard = TrieHard.new()
    @commands |> Enum.each(&TrieHard.insert(trie_hard, &1, true))
    trie_hard
  end

  defp build_retrieval, do: Retrieval.new(@commands)
  defp build_dimi_trie, do: Trie.put_words(@commands)

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
        [_ | _] -> raise "Mismatch looking up #{inspect(word)}: #{inspect(results)}"
      end
    end)
  end

  defp search_trie_hard(trie, input) do
    case TrieHard.auto_complete(trie, input, 10) do
      {:ok, []} -> {:error, :not_found}
      {:ok, [match]} -> {:ok, match}
      {:ok, [_ | _] = list} -> {:error, :ambiguous, Enum.sort(list)}
    end
  end

  defp search_retrieval(trie, input) do
    case Retrieval.prefix(trie, input) do
      [] -> {:error, :not_found}
      [match] -> {:ok, match}
      [_ | _] = list -> {:error, :ambiguous, Enum.sort(list)}
    end
  end

  defp search_dimi_trie(trie, input) do
    case Trie.search(trie, input) do
      [] -> {:error, :not_found}
      [match] -> {:ok, match}
      [_ | _] = list -> {:error, :ambiguous, Enum.sort(list)}
    end
  end
end
