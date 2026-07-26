# TrieBenchmark

Simple benchmark of three different Trie implementations for Elixir.

## Motivation

I'm working on [recreating MUSH in Elixir](https://github.com/wisq/ex_mush) and was looking for a trie implementation to use for matching commands.  (The contents of the trie are literally just the output of `@list commands` in PennMUSH.)

## Installation

 - `mix deps.get`
 - `patch -p0 < deps.patch`
   - This patches the older dependencies to let them compile and run warning-free on Elixir 1.20.
 - `mix run`

## Results

```
Generated 800 words from commands in 1516 µs.
Generated 200 words from dict in 122748 µs.
Operating System: macOS
CPU Information: Apple M2 Max
Number of Available Cores: 12
Available memory: 96 GB
Elixir 1.20.2
Erlang 29.0.3
JIT enabled: true

Benchmark suite executing with the following configuration:
warmup: 2 s
time: 10 s
memory time: 2 s
reduction time: 0 ns
parallel: 1
inputs: none specified
Estimated total run time: 56 s
Excluding outliers: false

Benchmarking trie_hard ...
Benchmarking retrieval ...
Benchmarking dimi_trie ...
Benchmarking using_ets ...
Calculating statistics...
Formatting results...

Name                ips        average  deviation         median         99th %
using_ets        3.11 K      322.00 μs     ±3.23%      324.25 μs      345.36 μs
retrieval        2.96 K      338.29 μs     ±2.76%      338.79 μs      361.58 μs
trie_hard        2.13 K      468.88 μs     ±5.08%      471.04 μs      508.91 μs
dimi_trie        1.38 K      725.28 μs     ±2.62%      731.21 μs      758.57 μs

Comparison: 
using_ets        3.11 K
retrieval        2.96 K - 1.05x slower +16.28 μs
trie_hard        2.13 K - 1.46x slower +146.88 μs
dimi_trie        1.38 K - 2.25x slower +403.28 μs

Memory usage statistics:

Name         Memory usage
using_ets       185.53 KB
retrieval      1014.48 KB - 5.47x memory usage +828.95 KB
trie_hard       122.66 KB - 0.66x memory usage -62.86719 KB
dimi_trie      1576.02 KB - 8.49x memory usage +1390.49 KB

**All measurements for memory usage were the same**
```

## Analysis

I did not expect `retrieval` (pure Elixir code that hasn't been touched in ten years) to beat `trie_hard` (Rust code from just ten months ago) on execution time.  (`trie_hard` still beats it strongly on memory usage, though.)

I initially assumed this is because I have a fairly small set of commands, and a larger trie might give `trie_hard` the advantage.  But I found the exact opposite: When I added 10000 random dictionary words (increasing size by >50x), `trie_hard`'s relative performance actually dropped to the bottom, below both of the Elixir-native libraries.

But the real surprise here is that the ETS approach manages to beat all of the above — and that its advantage actually grows larger with trie size.  This is especially surprising because it isn't technically a trie at all — an ETS `ordered_set` is a binary search tree (BST) based on Erlang term order.

I already used the ETS approach [in ExMUSH](https://github.com/wisq/ex_mush/blob/5738cce4462dba5ebc1b8305dfc1d75582d72c31/lib/ex_mush/world/object_directory.ex#L57) to index and lookup players by name.  At the time, it seemed like a neat way to use ETSes to do a partial match, but I had no idea it was actually quite efficient as well.

In theory, the ETS approach should have almost everything stacked against it in this benchmark:

 - It has to first do an extra check for exact match;
 - The code has to `:ets.next` through every match to find the first non-match (recursively creating a list of matches); and,
 - For the purposes of benchmark parity, unlike ExMUSH's player matching ...
  - I don't get to take advantage of storing real usable data in the value,
  - nor do I get to just immediately stop when I realise the match is ambiguous.

I initially included it to see how much better a trie would be … only to discover the results showed the exact opposite.  Never underestimate the Erlang devs, I guess.
