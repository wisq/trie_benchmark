# TrieBenchmark

Simple benchmark of three different trie implementations for Elixir (plus a surprise fourth non-trie contestant).

## Motivation

I'm working on [recreating MUSH in Elixir](https://github.com/wisq/ex_mush) and was looking for a trie implementation to use for matching commands.  (Initially, the contents of the trie were literally just the output of `@list commands` in PennMUSH.)

## Installation

 - `mix deps.get`
 - `patch -p0 < deps.patch`
   - This patches the older dependencies to let them compile and run warning-free on Elixir 1.20.
 - `mix run`

## Results

This suite runs three benchmarks of increasingly larger size.  To see the results, click each section to expand it.

<details>
  <summary>For the 175 PennMUSH commands</summary>

```
**** Running with 175 possible commands (max per query: 10) ****

Generated 800 words from commands in 4398 µs.
Generated 200 words from dict in 120890 µs.
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
using_ets        2.85 K      351.32 μs     ±4.18%      360.67 μs      382.40 μs
retrieval        2.45 K      408.02 μs     ±4.06%      399.04 μs      439.46 μs
trie_hard        1.87 K      535.42 μs     ±2.98%         531 μs      593.36 μs
dimi_trie        1.26 K      795.38 μs     ±3.75%      783.56 μs      847.95 μs

Comparison: 
using_ets        2.85 K
retrieval        2.45 K - 1.16x slower +56.70 μs
trie_hard        1.87 K - 1.52x slower +184.09 μs
dimi_trie        1.26 K - 2.26x slower +444.06 μs

Memory usage statistics:

Name         Memory usage
using_ets         0.23 MB
retrieval         1.42 MB - 6.11x memory usage +1.19 MB
trie_hard        0.157 MB - 0.67x memory usage -0.07615 MB
dimi_trie         1.80 MB - 7.71x memory usage +1.56 MB

**All measurements for memory usage were the same**
```
</details>

<details>
  <summary>For 10000 random words</summary>

```
**** Running with 10000 possible commands (max per query: 100) ****

Generated 800 words from commands in 211130 µs.
Generated 200 words from dict in 113128 µs.
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
using_ets        907.64        1.10 ms     ±2.32%        1.11 ms        1.15 ms
retrieval        414.42        2.41 ms     ±2.55%        2.42 ms        2.51 ms
trie_hard        340.82        2.93 ms     ±1.88%        2.95 ms        3.04 ms
dimi_trie        303.03        3.30 ms     ±1.17%        3.29 ms        3.41 ms

Comparison: 
using_ets        907.64
retrieval        414.42 - 2.19x slower +1.31 ms
trie_hard        340.82 - 2.66x slower +1.83 ms
dimi_trie        303.03 - 3.00x slower +2.20 ms

Memory usage statistics:

Name         Memory usage
using_ets         0.94 MB
retrieval        10.05 MB - 10.63x memory usage +9.10 MB
trie_hard         0.83 MB - 0.88x memory usage -0.11457 MB
dimi_trie         7.62 MB - 8.06x memory usage +6.67 MB

**All measurements for memory usage were the same**
```
</details>

<details>
  <summary>For 100,000 random words</summary>

```
**** Running with 100000 possible commands (max per query: 1000) ****

Generated 800 words from commands in 2154332 µs.
Generated 200 words from dict in 83181 µs.
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
using_ets        185.22        5.40 ms     ±4.40%        5.26 ms        5.90 ms
retrieval         45.92       21.78 ms     ±2.04%       21.76 ms       22.29 ms
dimi_trie         41.09       24.34 ms     ±2.36%       24.24 ms       25.10 ms
trie_hard         34.58       28.92 ms     ±1.77%       28.89 ms       30.78 ms

Comparison: 
using_ets        185.22
retrieval         45.92 - 4.03x slower +16.38 ms
dimi_trie         41.09 - 4.51x slower +18.94 ms
trie_hard         34.58 - 5.36x slower +23.52 ms

Memory usage statistics:

Name         Memory usage
using_ets         5.85 MB
retrieval        80.72 MB - 13.79x memory usage +74.87 MB
dimi_trie        55.73 MB - 9.52x memory usage +49.88 MB
trie_hard         7.28 MB - 1.24x memory usage +1.43 MB

**All measurements for memory usage were the same**
```
</details>

## Analysis

I did not expect `retrieval` (pure Elixir code that hasn't been touched in ten years) to beat `trie_hard` (Rust code from just ten months ago) on execution time.  (`trie_hard` still beats it strongly on memory usage, though.)

I initially assumed this is because I have a fairly small set of commands, and a larger trie might give `trie_hard` the advantage.  But I found the exact opposite: The more words I added to the trie, the more `trie_hard`'s relative performance dropped, eventually placing it on the bottom below both of the Elixir-native libraries.

But the real surprise here is that the ETS approach manages to beat all of the above — and that its advantage actually grows larger with trie size.  This is especially surprising because it isn't technically a trie at all — an ETS `ordered_set` is a binary search tree (BST) based on Erlang term order.

I already used the ETS approach [in ExMUSH](https://github.com/wisq/ex_mush/blob/5738cce4462dba5ebc1b8305dfc1d75582d72c31/lib/ex_mush/world/object_directory.ex#L57) to index and lookup players by name.  At the time, it seemed like a neat way to use ETSes to do a partial match, but I had no idea it was actually quite efficient as well.

In theory, the ETS approach should have almost everything stacked against it in this benchmark:

 - It has to first do an extra check for exact match;
 - The code has to `:ets.next` through every match to find the first non-match (recursively creating a list of matches); and,
 - For the purposes of benchmark parity, unlike ExMUSH's player matching ...
   - I don't get to take advantage of storing real usable data in the value,
   - nor do I get to just immediately stop when I realise the match is ambiguous.

I initially included it to see how much better a trie would be … only to discover the results showed the exact opposite.  Never underestimate the Erlang devs, I guess.
