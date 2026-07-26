# TrieBenchmark

Simple benchmark of three different trie implementations for Elixir (plus a surprise fourth non-trie contestant).

## Motivation

I'm working on [recreating MUSH in Elixir](https://github.com/wisq/ex_mush) and was looking for a trie implementation to use for matching commands.  (Initially, the contents of the trie were literally just the output of `@list commands` in PennMUSH.)

## Installation

 - `mix deps.get`
 - `patch -p0 < deps.patch`
   - This patches the older dependencies to let them compile and run warning-free on Elixir 1.20.
 - `mix run`

## Methodology

We test four different approaches to trie lookups:

 - [TrieHard](https://github.com/nyo16/trie_hard)
 - [Retrieval](https://github.com/Rob-bie/retrieval)
 - dimitarvp's [Trie](https://github.com/dimitarvp/trie), which I've called `dimi_trie` here for clarity
 - an ETS approach based on `ordered_set` iteration

### Data

We have four datasets (trie contents) to work with:

 - the 175 PennMUSH commands
 - random sampling of 1k, 10k, and 100k words
   - 7-bit clean, `[a-z]` only, no punctuation

Against each, we test 1000 different simulated user inputs:

 - 800 are taken from the commands
   - these will be a mixture of exact and partial matches of random length
 - 200 are taken from the dictionary
   - also a mix of whole words, and partial starts of words, of random length
   - some (or many) of the longer words / prefixes will probably be total misses, depending on the size of the command set
 - all shuffled in random order

Both these lists are generated before any benchmarking begins, and are the same within a single benchmark.

### Algorithms

#### Version 1 (`V1`)

V1 was my original benchmark, or close to it.  It had three return states:

 - `{:ok, match}` — exact match, or a partial match with only one possibility
 - `{:error, :no_match}` — no matches at all
 - `{:error, :ambiguous, list}` — a list of 2+ partial matches, sorted (so all algorithms had the same output)

Essentially, the idea was that I would generate a list of possible matches, and unless that list was excessively long, I might even suggest some of those matches to the user.

This turned out to start becoming problematic with the larger datasets (see "Fairness", below), so I created V2.

#### Version 2 (`V2`)

V2 has the same return values as V1, except that it only returns `{:error, :ambiguous}` on an ambiguous match.  This gives the advantage to the libraries that don't need to fetch every single partial match to discover that the input is ambiguous.

V2 also tested two different `trie_hard` approaches.  Both approaches check for an exact match first.  Then, the first approach (`triehard1`) immediately tries to use `auto_complete` to get up to two partial matches — either zero (no matches), one (partial match), or two (ambiguous match).  The second approach (`triehard2`) instead uses `count_prefix` to count them first, only bothering to fetch the partial match if the count is exactly one.  *(This turns out to **not** be a good optimisation — see "Conclusions", below.)*

### Fairness

It's difficult to compare these libraries fairly.  In nearly all of my tests, I've insisted that all three return the exact same value for any query, to ensure correctness.  But in the process, some algorithms have it easy, some have it hard.

Notably, there's some major differences between the four approaches:

 - `dimi_trie` does not have the ability to check for exact matches.  It **must** list every match for a given prefix — which also means that finding an exact match involves iterating through the list of prefix matches and seeing if the input is in there, verbatim.
 - Retrieval can search for exact matches, but cannot limit how many prefix matches are returned.  This means we can skip "search the entire list of prefix matches for an exact match", but we still have to retrieve all prefix matches, even if it's too many to realistically use.
 - TrieHard and ETS can both search for exact matches, and can both limit how many prefix matches are returned.  While making them more flexible, this also means they've effectively got one hand tied behind their back — they have to return the same value as the other algorithms, even if the number of matches is more than we would realistically use.

So what to do?

 - I could just have all algorithms return all partial matches at all times — "fair", but unrealistic for my use case, since I'm never going to use 100+ matches.
 - I could filter the input list to ensure no input matches more than `n` commands — also "fair", but incredibly unrealistic except in very specific use cases (and definitely not mine).
 - I could limit how many ambiguous matches each algorithm needs to return — realistic, but a huge advantage to ETS and TrieHard … though arguably they deserve the advantage for having that flexibility.

Ultimately, for each set of commands, I ended up doing four different benchmarks:

 - V1 with max 10 matches, with input filtering to avoid >10 matches.
 - V1 with max 10 matches, without input filtering.
   - This is the one case where our sanity check allows the query functions to return different results, so long as they all agree there are 10+ matches.
 - V1 with no maximum matches (all matches are returned), no input filtering.
 - V2, which is basically V1 but optimised for only 0, 1, or 2 matches.

I think this strikes a good balance between fairness, completeness, realism, etc.  You can pick whichever benchmark scenario fits your use case better — although spoilers, it may not be much of a choice, since there's one approach that wins every single time.

## Results

This suite uses four datasets of increasingly larger size.  Each dataset is used to benchmark four different approaches, for a total of sixteen benchmarks in all.  To see the results, click each section to expand it.

<details>
  <summary>For the 175 PennMUSH commands</summary>

```
**** Running V1 with 175 possible commands 10 possible matches, input fitering enabled ****

Generated 800 words from commands in 22874 µs.
Generated 200 words from dict in 137089 µs.
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
using_ets        2.86 K      350.16 μs     ±5.08%      342.92 μs      412.75 μs
retrieval        2.27 K      440.18 μs     ±3.04%      437.50 μs      487.58 μs
trie_hard        1.79 K      558.84 μs     ±2.67%      555.96 μs      613.96 μs
dimi_trie        1.23 K      815.99 μs     ±3.25%      800.67 μs      886.22 μs

Comparison: 
using_ets        2.86 K
retrieval        2.27 K - 1.26x slower +90.02 μs
trie_hard        1.79 K - 1.60x slower +208.68 μs
dimi_trie        1.23 K - 2.33x slower +465.83 μs

Memory usage statistics:

Name         Memory usage
using_ets         0.23 MB
retrieval         1.65 MB - 7.15x memory usage +1.42 MB
trie_hard        0.143 MB - 0.62x memory usage -0.08794 MB
dimi_trie         1.84 MB - 7.97x memory usage +1.61 MB

**All measurements for memory usage were the same**

**** Running V1 with 175 possible commands 10 possible matches, input fitering disabled ****

Generated 800 words from commands in 459 µs.
Generated 200 words from dict in 132803 µs.
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
using_ets        2.45 K        0.41 ms     ±4.46%        0.41 ms        0.46 ms
trie_hard        1.25 K        0.80 ms     ±4.23%        0.81 ms        0.89 ms
retrieval        0.21 K        4.79 ms     ±5.42%        4.69 ms        5.66 ms
dimi_trie       0.185 K        5.42 ms     ±1.62%        5.42 ms        5.67 ms

Comparison: 
using_ets        2.45 K
trie_hard        1.25 K - 1.97x slower +0.39 ms
retrieval        0.21 K - 11.74x slower +4.38 ms
dimi_trie       0.185 K - 13.29x slower +5.01 ms

Memory usage statistics:

Name         Memory usage
using_ets         0.31 MB
trie_hard        0.193 MB - 0.62x memory usage -0.11867 MB
retrieval        15.29 MB - 49.03x memory usage +14.98 MB
dimi_trie        10.83 MB - 34.73x memory usage +10.52 MB

**All measurements for memory usage were the same**

**** Running V1 with 175 possible commands all possible matches, input fitering enabled ****

Generated 800 words from commands in 450 µs.
Generated 200 words from dict in 124653 µs.
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
using_ets        767.33        1.30 ms     ±3.90%        1.30 ms        1.46 ms
trie_hard        252.18        3.97 ms     ±1.48%        3.96 ms        4.15 ms
dimi_trie        192.62        5.19 ms     ±1.78%        5.18 ms        5.44 ms
retrieval        185.81        5.38 ms     ±3.56%        5.34 ms        5.96 ms

Comparison: 
using_ets        767.33
trie_hard        252.18 - 3.04x slower +2.66 ms
dimi_trie        192.62 - 3.98x slower +3.89 ms
retrieval        185.81 - 4.13x slower +4.08 ms

Memory usage statistics:

Name              average  deviation         median         99th %
using_ets         1.49 MB     ±0.00%        1.49 MB        1.49 MB
trie_hard         0.81 MB     ±0.00%        0.81 MB        0.81 MB
dimi_trie        12.04 MB     ±0.00%       12.04 MB       12.04 MB
retrieval        17.12 MB     ±0.00%       17.12 MB       17.12 MB

Comparison: 
using_ets         1.49 MB
trie_hard         0.81 MB - 0.54x memory usage -0.68504 MB
dimi_trie        12.04 MB - 8.07x memory usage +10.55 MB
retrieval        17.12 MB - 11.48x memory usage +15.63 MB

**** Running V2 with 175 possible commands ****

Generated 800 words from commands in 430 µs.
Generated 200 words from dict in 124693 µs.
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
Estimated total run time: 1 min 10 s
Excluding outliers: false

Benchmarking retrieval ...
Benchmarking dimi_trie ...
Benchmarking using_ets ...
Benchmarking triehard1 ...
Benchmarking triehard2 ...
Calculating statistics...
Formatting results...

Name                ips        average  deviation         median         99th %
using_ets       3252.74        0.31 ms     ±4.54%        0.30 ms        0.36 ms
triehard1       1701.73        0.59 ms     ±2.49%        0.59 ms        0.63 ms
triehard2        352.32        2.84 ms     ±1.67%        2.83 ms        2.99 ms
dimi_trie        168.40        5.94 ms     ±9.18%        5.79 ms        8.48 ms
retrieval        161.51        6.19 ms     ±4.20%        6.12 ms        6.85 ms

Comparison: 
using_ets       3252.74
triehard1       1701.73 - 1.91x slower +0.28 ms
triehard2        352.32 - 9.23x slower +2.53 ms
dimi_trie        168.40 - 19.32x slower +5.63 ms
retrieval        161.51 - 20.14x slower +5.88 ms

Memory usage statistics:

Name              average  deviation         median         99th %
using_ets       144.20 KB     ±0.00%      144.20 KB      144.20 KB
triehard1       127.36 KB     ±0.00%      127.36 KB      127.36 KB
triehard2       632.90 KB     ±0.00%      632.90 KB      632.90 KB
dimi_trie     13742.87 KB     ±0.00%    13742.87 KB    13742.87 KB
retrieval     19711.95 KB     ±0.00%    19711.95 KB    19711.95 KB

Comparison: 
using_ets       144.20 KB
triehard1       127.36 KB - 0.88x memory usage -16.84375 KB
triehard2       632.90 KB - 4.39x memory usage +488.70 KB
dimi_trie     13742.87 KB - 95.30x memory usage +13598.66 KB
retrieval     19711.95 KB - 136.70x memory usage +19567.74 KB
```
</details>

<details>
  <summary>For 1000 random words</summary>

```
**** Running V1 with 1000 possible commands 10 possible matches, input fitering enabled ****

Generated 800 words from commands in 163860 µs.
Generated 200 words from dict in 154706 µs.
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
using_ets        2.22 K      450.30 μs     ±2.50%      447.38 μs      499.88 μs
retrieval        1.76 K      567.73 μs     ±2.69%      565.59 μs      626.82 μs
trie_hard        1.37 K      729.02 μs     ±2.23%      732.54 μs      770.75 μs
dimi_trie        1.00 K     1004.04 μs     ±2.31%     1000.09 μs     1093.84 μs

Comparison: 
using_ets        2.22 K
retrieval        1.76 K - 1.26x slower +117.44 μs
trie_hard        1.37 K - 1.62x slower +278.72 μs
dimi_trie        1.00 K - 2.23x slower +553.75 μs

Memory usage statistics:

Name         Memory usage
using_ets         0.24 MB
retrieval         2.02 MB - 8.50x memory usage +1.78 MB
trie_hard        0.136 MB - 0.57x memory usage -0.10195 MB
dimi_trie         2.25 MB - 9.45x memory usage +2.01 MB

**All measurements for memory usage were the same**

**** Running V1 with 1000 possible commands 10 possible matches, input fitering disabled ****

Generated 800 words from commands in 2090 µs.
Generated 200 words from dict in 146283 µs.
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
using_ets       1811.05        0.55 ms     ±2.52%        0.55 ms        0.62 ms
trie_hard        773.51        1.29 ms     ±1.99%        1.29 ms        1.39 ms
retrieval        305.14        3.28 ms     ±1.50%        3.26 ms        3.44 ms
dimi_trie        254.10        3.94 ms     ±1.30%        3.92 ms        4.10 ms

Comparison: 
using_ets       1811.05
trie_hard        773.51 - 2.34x slower +0.74 ms
retrieval        305.14 - 5.94x slower +2.72 ms
dimi_trie        254.10 - 7.13x slower +3.38 ms

Memory usage statistics:

Name         Memory usage
using_ets         0.37 MB
trie_hard         0.23 MB - 0.62x memory usage -0.14212 MB
retrieval        14.76 MB - 39.97x memory usage +14.39 MB
dimi_trie        10.32 MB - 27.95x memory usage +9.95 MB

**All measurements for memory usage were the same**

**** Running V1 with 1000 possible commands all possible matches, input fitering enabled ****

Generated 800 words from commands in 1799 µs.
Generated 200 words from dict in 150282 µs.
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
using_ets        836.06        1.20 ms     ±3.08%        1.19 ms        1.30 ms
retrieval        236.91        4.22 ms     ±1.26%        4.20 ms        4.41 ms
trie_hard        228.05        4.39 ms     ±1.39%        4.37 ms        4.58 ms
dimi_trie        189.69        5.27 ms    ±11.75%        5.08 ms        7.71 ms

Comparison: 
using_ets        836.06
retrieval        236.91 - 3.53x slower +3.03 ms
trie_hard        228.05 - 3.67x slower +3.19 ms
dimi_trie        189.69 - 4.41x slower +4.08 ms

Memory usage statistics:

Name         Memory usage
using_ets         1.18 MB
retrieval        19.31 MB - 16.34x memory usage +18.13 MB
trie_hard         0.68 MB - 0.58x memory usage -0.49983 MB
dimi_trie        13.27 MB - 11.23x memory usage +12.09 MB

**All measurements for memory usage were the same**

**** Running V2 with 1000 possible commands ****

Generated 800 words from commands in 1662 µs.
Generated 200 words from dict in 102995 µs.
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
Estimated total run time: 1 min 10 s
Excluding outliers: false

Benchmarking retrieval ...
Benchmarking dimi_trie ...
Benchmarking using_ets ...
Benchmarking triehard1 ...
Benchmarking triehard2 ...
Calculating statistics...
Formatting results...

Name                ips        average  deviation         median         99th %
using_ets       2469.21        0.40 ms     ±2.44%        0.40 ms        0.45 ms
triehard1       1218.63        0.82 ms     ±2.60%        0.82 ms        0.91 ms
retrieval        293.53        3.41 ms     ±1.49%        3.39 ms        3.57 ms
triehard2        268.71        3.72 ms     ±1.38%        3.71 ms        3.90 ms
dimi_trie        245.54        4.07 ms     ±2.77%        4.03 ms        4.45 ms

Comparison: 
using_ets       2469.21
triehard1       1218.63 - 2.03x slower +0.42 ms
retrieval        293.53 - 8.41x slower +3.00 ms
triehard2        268.71 - 9.19x slower +3.32 ms
dimi_trie        245.54 - 10.06x slower +3.67 ms

Memory usage statistics:

Name         Memory usage
using_ets       168.72 KB
triehard1       137.73 KB - 0.82x memory usage -30.98438 KB
retrieval     15612.29 KB - 92.53x memory usage +15443.57 KB
triehard2       616.92 KB - 3.66x memory usage +448.20 KB
dimi_trie     10886.73 KB - 64.53x memory usage +10718.01 KB

**All measurements for memory usage were the same**
```
</details>

<details>
  <summary>For 10,000 random words</summary>

```
**** Running V1 with 10000 possible commands 10 possible matches, input fitering enabled ****

Generated 800 words from commands in 1413329 µs.
Generated 200 words from dict in 420572 µs.
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
using_ets        1.73 K      578.65 μs     ±2.22%      575.17 μs      638.72 μs
retrieval        1.51 K      661.19 μs     ±5.94%      657.71 μs      758.08 μs
trie_hard        1.26 K      792.67 μs     ±2.26%      789.63 μs      863.07 μs
dimi_trie        0.82 K     1214.37 μs     ±4.66%     1211.63 μs     1349.84 μs

Comparison: 
using_ets        1.73 K
retrieval        1.51 K - 1.14x slower +82.54 μs
trie_hard        1.26 K - 1.37x slower +214.01 μs
dimi_trie        0.82 K - 2.10x slower +635.71 μs

Memory usage statistics:

Name         Memory usage
using_ets         0.25 MB
retrieval         1.99 MB - 7.97x memory usage +1.74 MB
trie_hard        0.153 MB - 0.61x memory usage -0.09705 MB
dimi_trie         2.33 MB - 9.34x memory usage +2.08 MB

**All measurements for memory usage were the same**

**** Running V1 with 10000 possible commands 10 possible matches, input fitering disabled ****

Generated 800 words from commands in 24320 µs.
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
Estimated total run time: 56 s
Excluding outliers: false

Benchmarking trie_hard ...
Benchmarking retrieval ...
Benchmarking dimi_trie ...
Benchmarking using_ets ...
Calculating statistics...
Formatting results...

Name                ips        average  deviation         median         99th %
using_ets       1266.55        0.79 ms     ±2.05%        0.78 ms        0.87 ms
trie_hard        581.61        1.72 ms     ±1.70%        1.72 ms        1.83 ms
retrieval         24.95       40.08 ms    ±11.69%       42.98 ms       46.29 ms
dimi_trie         24.58       40.68 ms     ±0.68%       40.63 ms       41.46 ms

Comparison: 
using_ets       1266.55
trie_hard        581.61 - 2.18x slower +0.93 ms
retrieval         24.95 - 50.76x slower +39.29 ms
dimi_trie         24.58 - 51.52x slower +39.89 ms

Memory usage statistics:

Name         Memory usage
using_ets         0.50 MB
trie_hard         0.32 MB - 0.65x memory usage -0.17729 MB
retrieval       150.14 MB - 300.22x memory usage +149.64 MB
dimi_trie        99.87 MB - 199.71x memory usage +99.37 MB

**All measurements for memory usage were the same**

**** Running V1 with 10000 possible commands all possible matches, input fitering enabled ****

Generated 800 words from commands in 26290 µs.
Generated 200 words from dict in 142697 µs.
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
using_ets        115.29        8.67 ms     ±3.38%        8.75 ms        9.29 ms
trie_hard         30.31       32.99 ms     ±1.07%       32.93 ms       34.13 ms
dimi_trie         25.98       38.49 ms     ±0.99%       38.41 ms       39.71 ms
retrieval         24.30       41.16 ms     ±4.17%       40.78 ms       51.72 ms

Comparison: 
using_ets        115.29
trie_hard         30.31 - 3.80x slower +24.32 ms
dimi_trie         25.98 - 4.44x slower +29.82 ms
retrieval         24.30 - 4.74x slower +32.48 ms

Memory usage statistics:

Name         Memory usage
using_ets         9.22 MB
trie_hard         4.56 MB - 0.49x memory usage -4.66603 MB
dimi_trie        91.70 MB - 9.94x memory usage +82.48 MB
retrieval       137.75 MB - 14.93x memory usage +128.52 MB

**All measurements for memory usage were the same**

**** Running V2 with 10000 possible commands ****

Generated 800 words from commands in 33446 µs.
Generated 200 words from dict in 127694 µs.
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
Estimated total run time: 1 min 10 s
Excluding outliers: false

Benchmarking retrieval ...
Benchmarking dimi_trie ...
Benchmarking using_ets ...
Benchmarking triehard1 ...
Benchmarking triehard2 ...
Calculating statistics...
Formatting results...

Name                ips        average  deviation         median         99th %
using_ets       1877.14        0.53 ms     ±1.93%        0.53 ms        0.58 ms
triehard1       1165.47        0.86 ms     ±2.15%        0.86 ms        0.93 ms
triehard2        155.00        6.45 ms     ±2.22%        6.37 ms        6.97 ms
retrieval         26.26       38.09 ms    ±10.25%       35.98 ms       48.87 ms
dimi_trie         24.01       41.65 ms     ±0.72%       41.62 ms       42.87 ms

Comparison: 
using_ets       1877.14
triehard1       1165.47 - 1.61x slower +0.33 ms
triehard2        155.00 - 12.11x slower +5.92 ms
retrieval         26.26 - 71.50x slower +37.56 ms
dimi_trie         24.01 - 78.19x slower +41.12 ms

Memory usage statistics:

Name         Memory usage
using_ets        0.161 MB
triehard1        0.142 MB - 0.88x memory usage -0.01913 MB
triehard2         1.12 MB - 6.96x memory usage +0.96 MB
retrieval       150.24 MB - 931.67x memory usage +150.08 MB
dimi_trie        99.96 MB - 619.88x memory usage +99.80 MB

**All measurements for memory usage were the same**
```
</details>

<details>
  <summary>For 100,000 random words</summary>

```
**** Running V1 with 100000 possible commands 10 possible matches, input fitering enabled ****

Generated 800 words from commands in 12770887 µs.
Generated 200 words from dict in 2989303 µs.
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
using_ets        1.46 K      683.24 μs     ±1.03%      682.13 μs      709.34 μs
retrieval        1.32 K      759.15 μs    ±14.17%      753.09 μs      882.05 μs
trie_hard        1.10 K      908.58 μs     ±2.06%      907.36 μs      978.12 μs
dimi_trie        0.77 K     1303.74 μs    ±14.61%     1209.63 μs     1555.44 μs

Comparison: 
using_ets        1.46 K
retrieval        1.32 K - 1.11x slower +75.91 μs
trie_hard        1.10 K - 1.33x slower +225.34 μs
dimi_trie        0.77 K - 1.91x slower +620.50 μs

Memory usage statistics:

Name         Memory usage
using_ets         0.26 MB
retrieval         1.91 MB - 7.23x memory usage +1.65 MB
trie_hard        0.196 MB - 0.74x memory usage -0.06888 MB
dimi_trie         2.49 MB - 9.42x memory usage +2.23 MB

**All measurements for memory usage were the same**

**** Running V1 with 100000 possible commands 10 possible matches, input fitering disabled ****

Generated 800 words from commands in 152667 µs.
Generated 200 words from dict in 145101 µs.
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
using_ets       1156.77        0.86 ms     ±1.65%        0.86 ms        0.93 ms
trie_hard        550.10        1.82 ms     ±1.70%        1.81 ms        1.96 ms
dimi_trie          3.59      278.26 ms     ±0.93%      277.59 ms      287.06 ms
retrieval          2.83      352.74 ms     ±7.13%      352.30 ms      389.58 ms

Comparison: 
using_ets       1156.77
trie_hard        550.10 - 2.10x slower +0.95 ms
dimi_trie          3.59 - 321.89x slower +277.40 ms
retrieval          2.83 - 408.04x slower +351.87 ms

Memory usage statistics:

Name         Memory usage
using_ets         0.48 MB
trie_hard         0.42 MB - 0.87x memory usage -0.06001 MB
dimi_trie       631.29 MB - 1326.56x memory usage +630.81 MB
retrieval       901.64 MB - 1894.67x memory usage +901.17 MB

**All measurements for memory usage were the same**

**** Running V1 with 100000 possible commands all possible matches, input fitering enabled ****

Generated 800 words from commands in 154087 µs.
Generated 200 words from dict in 143910 µs.
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
using_ets         17.45       57.32 ms     ±1.74%       57.24 ms       60.18 ms
dimi_trie          3.53      283.39 ms     ±0.85%      283.14 ms      295.19 ms
retrieval          3.22      310.30 ms     ±2.51%      308.12 ms      341.81 ms
trie_hard          2.94      340.08 ms     ±1.71%      338.80 ms      364.03 ms

Comparison: 
using_ets         17.45
dimi_trie          3.53 - 4.94x slower +226.08 ms
retrieval          3.22 - 5.41x slower +252.98 ms
trie_hard          2.94 - 5.93x slower +282.77 ms

Memory usage statistics:

Name         Memory usage
using_ets        44.90 MB
dimi_trie       658.29 MB - 14.66x memory usage +613.39 MB
retrieval       939.63 MB - 20.93x memory usage +894.73 MB
trie_hard        39.03 MB - 0.87x memory usage -5.86473 MB

**All measurements for memory usage were the same**

**** Running V2 with 100000 possible commands ****

Generated 800 words from commands in 165405 µs.
Generated 200 words from dict in 93864 µs.
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
Estimated total run time: 1 min 10 s
Excluding outliers: false

Benchmarking retrieval ...
Benchmarking dimi_trie ...
Benchmarking using_ets ...
Benchmarking triehard1 ...
Benchmarking triehard2 ...
Calculating statistics...
Formatting results...

Name                ips        average  deviation         median         99th %
using_ets       1685.03        0.59 ms     ±1.79%        0.59 ms        0.64 ms
triehard1       1349.31        0.74 ms     ±1.97%        0.74 ms        0.80 ms
triehard2        175.04        5.71 ms     ±1.51%        5.69 ms        6.03 ms
retrieval          8.02      124.73 ms     ±9.48%      126.88 ms      161.74 ms
dimi_trie          3.10      322.40 ms     ±0.76%      321.55 ms      330.85 ms

Comparison: 
using_ets       1685.03
triehard1       1349.31 - 1.25x slower +0.148 ms
triehard2        175.04 - 9.63x slower +5.12 ms
retrieval          8.02 - 210.18x slower +124.14 ms
dimi_trie          3.10 - 543.25x slower +321.80 ms

Memory usage statistics:

Name         Memory usage
using_ets        0.136 MB
triehard1        0.140 MB - 1.04x memory usage +0.00492 MB
triehard2         1.20 MB - 8.84x memory usage +1.06 MB
retrieval       443.16 MB - 3270.25x memory usage +443.03 MB
dimi_trie       742.06 MB - 5475.94x memory usage +741.93 MB

**All measurements for memory usage were the same**
```
</details>

## Analysis

My original testing was just the three libraries (no ETS) against the PennMUSH commands, each returning all matches, and limiting the input to avoid prefixes (like a bare `@` sign).  (So essentially, V1 with filtering.)  This was largely because "They should all return the same" was a fairly early condition I placed on my test suite, as I was brand new to all these libraries and wanted to ensure I was getting the code right.

In these early tests, I honestly did not expect `retrieval` (pure Elixir code that hasn't been touched in ten years) to beat `trie_hard` (Rust code from just ten months ago) on execution time.  I initially assumed this is because I have a fairly small set of commands, and a larger trie might give `trie_hard` the advantage.  But I found the exact opposite: As I started adding random words to the trie, `trie_hard`'s relative performance dropped, eventually placing it on the bottom below both of the Elixir-native libraries.

It was at this point that I added the ETS approach.  I had used an ETS for partial matches [in ExMUSH](https://github.com/wisq/ex_mush/blob/5738cce4462dba5ebc1b8305dfc1d75582d72c31/lib/ex_mush/world/object_directory.ex#L57) to index and lookup players by name.  At the time, it seemed like a neat way to use ETSes to do a partial match, but I assumed a proper trie would be faster.  Still, for completeness, I figured I should add my ETS approach to the benchmark, if only to see how much faster the trie approach was.

And this was where the real shocker happened: The ETS approach was immediately and decisively beating all of the other approaches — and its advantage actually grew larger with trie size.  This was especially surprising because ETS `ordered_set` isn't technically a trie at all, but rather, a binary search tree (BST) based on Erlang term order.

For the sake of completeness, I continued to expand the scenarios, adding variations and adjustments that would better match how I might use the library, or that would demonstrate the strengths or weaknesses of the various libraries.  In these variations, the three libraries jockeyed for position — but in every single scenario, the ETS approach came out on top.

## Conclusions & takeaways

### ETS dominates

I don't know the exact reason for this.  I assume it's some combination of

 - Erlang being lower level than Elixir,
 - not needing to call out to Rust,
 - a BST actually being a pretty decent choice for this problem, and/or
 - the Erlang devs just being good at what they do.
 
Either way, the ETS approach has basically all the benefits of the TrieHard API — you can exact match, partial match, count partial matches, etc etc.  It requires a bit of extra code compared to just calling the equivalent functions on TrieHard, but you get a 100% native solution that can already easily expose itself to all processes for concurrent access.

The one caveat is, **I have not tested table writes AT ALL.**  I don't even measure how long it takes to set up the initial tables, because I just don't care.  My use case is to generate the table once at startup, and then rarely modify it, if at all.  If your use case involves frequent and heavy table modification, you should absolutely do your own benchmarks.

### TrieHard is a close second when you don't need all partial matches

Amongst all the V2 tests, and all the V1 tests with input filtering disabled, you won't find a single case where TrieHard — or at least, `triehard1`, see below — isn't in second place.

The performance gains here have nothing to do with language or overall code efficiency.  It simply comes down to having the ability to only match `n` partial matches before you just throw your hands up and go "ambiguous, try again".  (That's why the ETS approach also sees similar gains in this scenario.)

#### The `triehard1` approach universally beat the `triehard2` approach

In hindsight, this makes a lot of sense.  In the V2 benchmark,

 - `triehard1` does a get-count-autocomplete (exact match, count partial matches, get partial match if `count == 1`), while
 - `triehard2` does a get-autocomplete (exact match, get up to 2 partial matches, successful match if we only get 1 partial).

My initial thought was that doing a count would save us from needlessly retrieving table data.  But if the input is highly ambiguous, counting the matches can involve **a lot** of table traversal.  Returning just two matches is incredibly easy by comparison.

### If you always need a complete list of partial matches, Retrieval is fine

Retrieval actually beats TrieHard in several of the "V1 with input filtering" and "V1 with all matches retrieved" scenarios.  It's a solid library for what it does (and its age), it just lacks some of the functions that make TrieHard and ETS more useful for typical real-world uses.

### dimitarvp's Trie is mainly useful if you don't need exact matches

Unfortunately, the lack of an ability to directly query for an exact match is really painful here.  The fact that e.g. "car" can match "card", "cartwheel", "cardamom", "carve", "carrot", etc etc, makes it really difficult to just check if "car" is in a typical dictionary using this library.

Obviously, you can always maintain a `Map` alongside your `Trie` if exact matches are important to you, but all the other approaches offer this functionality in the same data structure.

This library also spent most of its time around the bottom of the performance charts, with one major exception — in the V1 case with 100k commands, all matches, and no filtering, it actually outperformed everything except ETS.  (Granted, ETS still outperformed it by nearly 5x.)
