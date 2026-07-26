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
Generated 800 words from commands in 1106 µs.
Generated 200 words from dict in 128701 µs.
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
Estimated total run time: 42 s
Excluding outliers: false

Benchmarking trie_hard ...
Benchmarking retrieval ...
Benchmarking dimi_trie ...
Calculating statistics...
Formatting results...

Name                ips        average  deviation         median         99th %
retrieval        2.75 K      363.08 μs     ±2.05%      363.13 μs      385.78 μs
trie_hard        2.01 K      497.46 μs     ±1.89%         497 μs      517.88 μs
dimi_trie        1.30 K      772.12 μs     ±1.29%         769 μs      806.98 μs

Comparison: 
retrieval        2.75 K
trie_hard        2.01 K - 1.37x slower +134.38 μs
dimi_trie        1.30 K - 2.13x slower +409.04 μs

Memory usage statistics:

Name         Memory usage
retrieval         1.09 MB
trie_hard        0.127 MB - 0.12x memory usage -0.96129 MB
dimi_trie         1.58 MB - 1.45x memory usage +0.49 MB

**All measurements for memory usage were the same**
```

## Analysis

I did not expect `retrieval` (which hasn't been touched in ten years) to beat `trie_hard` (which was made just ten months ago) on execution time.  I assume this is because I have a fairly small set of commands, and a larger trie might give `trie_hard` the advantage. (`trie_hard` still wins strongly on memory usage, though.)
