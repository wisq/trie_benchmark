defmodule TrieBenchmark do
  use Application

  @pennmush_commands ~w{
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
    unless iex_running?(), do: run()
    {:ok, self()}
  end

  defp run do
    wordlist = words_from_dict() |> Enum.take(100_000)

    [
      @pennmush_commands,
      wordlist |> Enum.take_random(1000),
      wordlist |> Enum.take_random(10000),
      wordlist
    ]
    |> Enum.each(fn words ->
      TrieBenchmark.V1.run(words, max_matches: 10, filter_input: true)
      TrieBenchmark.V1.run(words, max_matches: 10, filter_input: false)
      TrieBenchmark.V1.run(words, max_matches: :all)
      TrieBenchmark.V2.run(words)
    end)
  end

  def words_from_commands(commands) do
    Stream.repeatedly(fn ->
      Enum.random(commands)
    end)
  end

  def words_from_dict do
    File.stream!("/usr/share/dict/words")
    |> Enum.shuffle()
    |> Stream.map(&:string.chomp/1)
    |> Stream.filter(&(&1 =~ ~r{^[a-z]+$}))
  end

  def partial_words(words) do
    words
    |> Stream.map(fn word ->
      len = String.length(word)
      String.slice(word, 0, Enum.random(1..len))
    end)
  end

  defp iex_running? do
    Code.ensure_loaded?(IEx) && IEx.started?()
  end
end
