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
**** Running V1 with 175 possible commands, 10 possible matches, input fitering enabled ****

Generated 800 words from commands in 20640 µs.
Generated 200 words from dict in 138007 µs.
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
using_ets        2.93 K      341.28 μs     ±4.01%      332.92 μs      373.67 μs
retrieval        2.35 K      425.14 μs     ±2.31%      424.25 μs      461.75 μs
trie_hard        1.81 K      552.93 μs     ±2.17%         552 μs      594.82 μs
dimi_trie        1.27 K      789.77 μs     ±2.77%      780.67 μs      855.52 μs

Comparison: 
using_ets        2.93 K
retrieval        2.35 K - 1.25x slower +83.86 μs
trie_hard        1.81 K - 1.62x slower +211.65 μs
dimi_trie        1.27 K - 2.31x slower +448.48 μs

Memory usage statistics:

Name         Memory usage
using_ets         0.23 MB
retrieval         1.59 MB - 7.02x memory usage +1.36 MB
trie_hard        0.141 MB - 0.62x memory usage -0.08486 MB
dimi_trie         1.80 MB - 7.96x memory usage +1.57 MB

**All measurements for memory usage were the same**

**** Running V1 with 175 possible commands, 10 possible matches, input fitering disabled ****

Generated 800 words from commands in 459 µs.
Generated 200 words from dict in 168917 µs.
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
using_ets        2.42 K        0.41 ms     ±4.19%        0.42 ms        0.45 ms
trie_hard        1.17 K        0.85 ms     ±4.23%        0.86 ms        0.92 ms
retrieval        0.20 K        4.97 ms     ±2.99%        4.94 ms        5.50 ms
dimi_trie       0.191 K        5.23 ms     ±9.39%        5.03 ms        6.43 ms

Comparison: 
using_ets        2.42 K
trie_hard        1.17 K - 2.06x slower +0.44 ms
retrieval        0.20 K - 12.01x slower +4.55 ms
dimi_trie       0.191 K - 12.65x slower +4.82 ms

Memory usage statistics:

Name         Memory usage
using_ets         0.32 MB
trie_hard         0.20 MB - 0.62x memory usage -0.12187 MB
retrieval        16.53 MB - 50.97x memory usage +16.20 MB
dimi_trie        11.63 MB - 35.87x memory usage +11.30 MB

**All measurements for memory usage were the same**

**** Running V1 with 175 possible commands, all possible matches ****

Generated 800 words from commands in 532 µs.
Generated 200 words from dict in 124880 µs.
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
using_ets        746.56        1.34 ms     ±3.86%        1.35 ms        1.47 ms
trie_hard        238.64        4.19 ms     ±0.98%        4.20 ms        4.28 ms
dimi_trie        187.70        5.33 ms     ±1.58%        5.32 ms        5.53 ms
retrieval        179.30        5.58 ms     ±3.42%        5.52 ms        6.11 ms

Comparison: 
using_ets        746.56
trie_hard        238.64 - 3.13x slower +2.85 ms
dimi_trie        187.70 - 3.98x slower +3.99 ms
retrieval        179.30 - 4.16x slower +4.24 ms

Memory usage statistics:

Name         Memory usage
using_ets         1.56 MB
trie_hard         0.85 MB - 0.54x memory usage -0.71501 MB
dimi_trie        12.61 MB - 8.07x memory usage +11.04 MB
retrieval        17.98 MB - 11.51x memory usage +16.42 MB

**All measurements for memory usage were the same**

**** Running V2 with 175 possible commands ****

Generated 800 words from commands in 512 µs.
Generated 200 words from dict in 138854 µs.
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
using_ets       3329.24        0.30 ms     ±4.07%        0.30 ms        0.33 ms
triehard1       1660.78        0.60 ms     ±3.91%        0.61 ms        0.64 ms
triehard2        374.87        2.67 ms     ±1.02%        2.67 ms        2.75 ms
retrieval        176.29        5.67 ms     ±3.63%        5.62 ms        6.41 ms
dimi_trie        151.63        6.60 ms    ±11.18%        6.95 ms        8.04 ms

Comparison: 
using_ets       3329.24
triehard1       1660.78 - 2.00x slower +0.30 ms
triehard2        374.87 - 8.88x slower +2.37 ms
retrieval        176.29 - 18.88x slower +5.37 ms
dimi_trie        151.63 - 21.96x slower +6.29 ms

Memory usage statistics:

Name              average  deviation         median         99th %
using_ets       143.23 KB     ±0.00%      143.23 KB      143.23 KB
triehard1       127.02 KB     ±0.00%      127.02 KB      127.02 KB
triehard2       578.16 KB     ±0.00%      578.16 KB      578.16 KB
retrieval     18482.30 KB     ±0.00%    18482.30 KB    18482.30 KB
dimi_trie     12957.66 KB     ±0.00%    12957.66 KB    12957.66 KB

Comparison: 
using_ets       143.23 KB
triehard1       127.02 KB - 0.89x memory usage -16.20313 KB
triehard2       578.16 KB - 4.04x memory usage +434.93 KB
retrieval     18482.30 KB - 129.04x memory usage +18339.07 KB
dimi_trie     12957.66 KB - 90.47x memory usage +12814.43 KB
```
</details>

<details>
  <summary>For 1000 random words</summary>

```
**** Running V1 with 1000 possible commands, 10 possible matches, input fitering enabled ****

Generated 800 words from commands in 165793 µs.
Generated 200 words from dict in 152761 µs.
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
using_ets        2.28 K      438.67 μs     ±3.32%      444.87 μs      462.51 μs
retrieval        1.74 K      574.21 μs     ±2.67%      577.66 μs      601.10 μs
trie_hard        1.33 K      749.08 μs     ±3.62%      759.33 μs      798.37 μs
dimi_trie        0.99 K     1012.33 μs     ±2.82%     1023.78 μs     1059.35 μs

Comparison: 
using_ets        2.28 K
retrieval        1.74 K - 1.31x slower +135.54 μs
trie_hard        1.33 K - 1.71x slower +310.41 μs
dimi_trie        0.99 K - 2.31x slower +573.66 μs

Memory usage statistics:

Name         Memory usage
using_ets         0.24 MB
retrieval         2.15 MB - 8.97x memory usage +1.91 MB
trie_hard        0.142 MB - 0.59x memory usage -0.09818 MB
dimi_trie         2.33 MB - 9.71x memory usage +2.09 MB

**All measurements for memory usage were the same**

**** Running V1 with 1000 possible commands, 10 possible matches, input fitering disabled ****

Generated 800 words from commands in 1930 µs.
Generated 200 words from dict in 150073 µs.
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
using_ets       1812.33        0.55 ms     ±3.01%        0.56 ms        0.58 ms
trie_hard        746.40        1.34 ms     ±2.76%        1.35 ms        1.40 ms
retrieval        260.40        3.84 ms     ±1.80%        3.87 ms        3.96 ms
dimi_trie        209.31        4.78 ms     ±0.87%        4.78 ms        4.91 ms

Comparison: 
using_ets       1812.33
trie_hard        746.40 - 2.43x slower +0.79 ms
retrieval        260.40 - 6.96x slower +3.29 ms
dimi_trie        209.31 - 8.66x slower +4.23 ms

Memory usage statistics:

Name         Memory usage
using_ets         0.38 MB
trie_hard         0.23 MB - 0.62x memory usage -0.14467 MB
retrieval        17.72 MB - 46.81x memory usage +17.34 MB
dimi_trie        12.22 MB - 32.28x memory usage +11.84 MB

**All measurements for memory usage were the same**

**** Running V1 with 1000 possible commands, all possible matches ****

Generated 800 words from commands in 2279 µs.
Generated 200 words from dict in 148681 µs.
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
using_ets        893.24        1.12 ms     ±3.19%        1.13 ms        1.18 ms
retrieval        259.07        3.86 ms     ±1.45%        3.87 ms        4.01 ms
trie_hard        240.70        4.15 ms     ±1.40%        4.15 ms        4.43 ms
dimi_trie        212.21        4.71 ms     ±1.54%        4.74 ms        4.86 ms

Comparison: 
using_ets        893.24
retrieval        259.07 - 3.45x slower +2.74 ms
trie_hard        240.70 - 3.71x slower +3.04 ms
dimi_trie        212.21 - 4.21x slower +3.59 ms

Memory usage statistics:

Name         Memory usage
using_ets         1.12 MB
retrieval        18.02 MB - 16.13x memory usage +16.90 MB
trie_hard         0.63 MB - 0.56x memory usage -0.48742 MB
dimi_trie        12.44 MB - 11.13x memory usage +11.32 MB

**All measurements for memory usage were the same**

**** Running V2 with 1000 possible commands ****

Generated 800 words from commands in 2241 µs.
Generated 200 words from dict in 144635 µs.
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
using_ets       2515.74        0.40 ms     ±2.21%        0.40 ms        0.42 ms
triehard1       1269.95        0.79 ms     ±3.74%        0.80 ms        0.84 ms
triehard2        251.21        3.98 ms     ±1.29%        4.00 ms        4.12 ms
retrieval        239.59        4.17 ms    ±13.09%        4.04 ms        6.72 ms
dimi_trie        206.20        4.85 ms     ±0.94%        4.86 ms        4.96 ms

Comparison: 
using_ets       2515.74
triehard1       1269.95 - 1.98x slower +0.39 ms
triehard2        251.21 - 10.01x slower +3.58 ms
retrieval        239.59 - 10.50x slower +3.78 ms
dimi_trie        206.20 - 12.20x slower +4.45 ms

Memory usage statistics:

Name         Memory usage
using_ets       164.39 KB
triehard1       134.97 KB - 0.82x memory usage -29.42188 KB
triehard2       658.70 KB - 4.01x memory usage +494.31 KB
retrieval     18484.42 KB - 112.44x memory usage +18320.03 KB
dimi_trie     12743.24 KB - 77.52x memory usage +12578.85 KB

**All measurements for memory usage were the same**
```
</details>

<details>
  <summary>For 10,000 random words</summary>

```
**** Running V1 with 10000 possible commands, 10 possible matches, input fitering enabled ****

Generated 800 words from commands in 1365876 µs.
Generated 200 words from dict in 449839 µs.
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
using_ets        1.78 K      562.94 μs     ±3.10%      569.83 μs      593.83 μs
retrieval        1.61 K      622.31 μs     ±4.47%      610.50 μs      682.45 μs
trie_hard        1.30 K      771.12 μs     ±2.86%      776.37 μs      819.66 μs
dimi_trie        0.86 K     1156.14 μs     ±2.97%     1162.91 μs     1246.94 μs

Comparison: 
using_ets        1.78 K
retrieval        1.61 K - 1.11x slower +59.36 μs
trie_hard        1.30 K - 1.37x slower +208.18 μs
dimi_trie        0.86 K - 2.05x slower +593.19 μs

Memory usage statistics:

Name         Memory usage
using_ets         0.25 MB
retrieval         1.90 MB - 7.69x memory usage +1.65 MB
trie_hard        0.153 MB - 0.62x memory usage -0.09419 MB
dimi_trie         2.30 MB - 9.30x memory usage +2.05 MB

**All measurements for memory usage were the same**

**** Running V1 with 10000 possible commands, 10 possible matches, input fitering disabled ****

Generated 800 words from commands in 24208 µs.
Generated 200 words from dict in 129073 µs.
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
using_ets       1290.79        0.77 ms     ±1.43%        0.77 ms        0.81 ms
trie_hard        575.22        1.74 ms     ±1.40%        1.74 ms        1.80 ms
dimi_trie         26.07       38.36 ms     ±0.52%       38.35 ms       38.90 ms
retrieval         24.08       41.52 ms     ±0.75%       41.53 ms       42.33 ms

Comparison: 
using_ets       1290.79
trie_hard        575.22 - 2.24x slower +0.96 ms
dimi_trie         26.07 - 49.51x slower +37.58 ms
retrieval         24.08 - 53.60x slower +40.75 ms

Memory usage statistics:

Name         Memory usage
using_ets         0.49 MB
trie_hard         0.33 MB - 0.66x memory usage -0.16483 MB
dimi_trie        95.75 MB - 194.93x memory usage +95.26 MB
retrieval       143.77 MB - 292.70x memory usage +143.28 MB

**All measurements for memory usage were the same**

**** Running V1 with 10000 possible commands, all possible matches ****

Generated 800 words from commands in 24950 µs.
Generated 200 words from dict in 123383 µs.
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
using_ets        124.85        8.01 ms     ±2.77%        8.04 ms        8.39 ms
trie_hard         32.55       30.72 ms     ±0.84%       30.65 ms       31.52 ms
dimi_trie         28.89       34.61 ms     ±0.74%       34.60 ms       35.54 ms
retrieval         28.44       35.17 ms     ±2.82%       35.73 ms       36.35 ms

Comparison: 
using_ets        124.85
trie_hard         32.55 - 3.84x slower +22.71 ms
dimi_trie         28.89 - 4.32x slower +26.60 ms
retrieval         28.44 - 4.39x slower +27.16 ms

Memory usage statistics:

Name         Memory usage
using_ets         8.45 MB
trie_hard         4.32 MB - 0.51x memory usage -4.12563 MB
dimi_trie        85.51 MB - 10.12x memory usage +77.06 MB
retrieval       128.26 MB - 15.18x memory usage +119.81 MB

**All measurements for memory usage were the same**

**** Running V2 with 10000 possible commands ****

Generated 800 words from commands in 27862 µs.
Generated 200 words from dict in 126580 µs.
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
using_ets       1915.84        0.52 ms     ±2.17%        0.52 ms        0.55 ms
triehard1       1152.70        0.87 ms     ±2.53%        0.87 ms        0.91 ms
triehard2        162.84        6.14 ms     ±2.12%        6.19 ms        6.41 ms
retrieval         38.26       26.14 ms     ±3.26%       25.71 ms       27.93 ms
dimi_trie         31.54       31.71 ms     ±0.66%       31.68 ms       32.80 ms

Comparison: 
using_ets       1915.84
triehard1       1152.70 - 1.66x slower +0.35 ms
triehard2        162.84 - 11.76x slower +5.62 ms
retrieval         38.26 - 50.07x slower +25.62 ms
dimi_trie         31.54 - 60.75x slower +31.19 ms

Memory usage statistics:

Name         Memory usage
using_ets        0.159 MB
triehard1        0.142 MB - 0.89x memory usage -0.01712 MB
triehard2         1.07 MB - 6.70x memory usage +0.91 MB
retrieval       113.93 MB - 715.41x memory usage +113.77 MB
dimi_trie        78.65 MB - 493.85x memory usage +78.49 MB

**All measurements for memory usage were the same**
```
</details>

<details>
  <summary>For 100,000 random words</summary>

```
**** Running V1 with 100000 possible commands, 10 possible matches, input fitering enabled ****

Generated 800 words from commands in 11633359 µs.
Generated 200 words from dict in 2977319 µs.
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
using_ets        1.39 K      721.70 μs     ±1.16%      720.53 μs      752.38 μs
retrieval        1.30 K      769.20 μs    ±15.21%      784.47 μs      927.12 μs
trie_hard        1.08 K      923.15 μs     ±3.25%      932.28 μs      970.25 μs
dimi_trie        0.77 K     1303.12 μs    ±17.15%     1212.95 μs     1738.30 μs

Comparison: 
using_ets        1.39 K
retrieval        1.30 K - 1.07x slower +47.50 μs
trie_hard        1.08 K - 1.28x slower +201.45 μs
dimi_trie        0.77 K - 1.81x slower +581.41 μs

Memory usage statistics:

Name         Memory usage
using_ets         0.29 MB
retrieval         2.04 MB - 6.91x memory usage +1.74 MB
trie_hard         0.20 MB - 0.69x memory usage -0.09048 MB
dimi_trie         2.55 MB - 8.66x memory usage +2.26 MB

**All measurements for memory usage were the same**

**** Running V1 with 100000 possible commands, 10 possible matches, input fitering disabled ****

Generated 800 words from commands in 131342 µs.
Generated 200 words from dict in 110388 µs.
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
using_ets       1114.43        0.90 ms     ±1.49%        0.90 ms        0.94 ms
trie_hard        543.55        1.84 ms     ±0.97%        1.84 ms        1.91 ms
dimi_trie          3.11      321.80 ms     ±0.67%      321.46 ms      332.19 ms
retrieval          2.60      384.12 ms     ±2.25%      383.72 ms      423.60 ms

Comparison: 
using_ets       1114.43
trie_hard        543.55 - 2.05x slower +0.94 ms
dimi_trie          3.11 - 358.62x slower +320.90 ms
retrieval          2.60 - 428.07x slower +383.22 ms

Memory usage statistics:

Name         Memory usage
using_ets       514.34 KB
trie_hard       430.45 KB - 0.84x memory usage -83.88281 KB
dimi_trie    772356.63 KB - 1501.66x memory usage +771842.30 KB
retrieval   1101846.63 KB - 2142.27x memory usage +1101332.30 KB

**All measurements for memory usage were the same**

**** Running V1 with 100000 possible commands, all possible matches ****

Generated 800 words from commands in 144886 µs.
Generated 200 words from dict in 139166 µs.
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
using_ets         17.83       56.08 ms     ±7.33%       55.59 ms       67.69 ms
dimi_trie          3.45      289.49 ms     ±0.68%      289.20 ms      299.83 ms
trie_hard          2.94      340.01 ms     ±0.56%      340.05 ms      346.28 ms
retrieval          2.91      343.10 ms     ±1.19%      342.28 ms      359.49 ms

Comparison: 
using_ets         17.83
dimi_trie          3.45 - 5.16x slower +233.41 ms
trie_hard          2.94 - 6.06x slower +283.93 ms
retrieval          2.91 - 6.12x slower +287.02 ms

Memory usage statistics:

Name         Memory usage
using_ets        50.48 MB
dimi_trie       677.16 MB - 13.42x memory usage +626.69 MB
trie_hard        39.52 MB - 0.78x memory usage -10.95693 MB
retrieval       966.18 MB - 19.14x memory usage +915.70 MB

**All measurements for memory usage were the same**

**** Running V2 with 100000 possible commands ****

Generated 800 words from commands in 152969 µs.
Generated 200 words from dict in 89789 µs.
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
using_ets       1616.58        0.62 ms     ±1.13%        0.62 ms        0.65 ms
triehard1       1266.30        0.79 ms     ±2.38%        0.79 ms        0.86 ms
triehard2        163.65        6.11 ms     ±0.62%        6.10 ms        6.28 ms
retrieval          4.86      205.81 ms     ±4.52%      212.78 ms      220.99 ms
dimi_trie          3.45      289.82 ms     ±2.18%      288.03 ms      318.62 ms

Comparison: 
using_ets       1616.58
triehard1       1266.30 - 1.28x slower +0.171 ms
triehard2        163.65 - 9.88x slower +5.49 ms
retrieval          4.86 - 332.71x slower +205.19 ms
dimi_trie          3.45 - 468.52x slower +289.21 ms

Memory usage statistics:

Name         Memory usage
using_ets        0.144 MB
triehard1        0.144 MB - 1.00x memory usage -0.00027 MB
triehard2         1.23 MB - 8.51x memory usage +1.08 MB
retrieval       586.41 MB - 4068.47x memory usage +586.26 MB
dimi_trie       660.71 MB - 4584.01x memory usage +660.57 MB

**All measurements for memory usage were the same**
```
</details>

## Analysis

My original testing was just the three libraries (no ETS) against the PennMUSH commands, each returning all matches, and limiting the input to avoid prefixes (like a bare `@` sign).  (So essentially, V1 with filtering.)  This was largely because "They should all return the same" was a fairly early condition I placed on my test suite, as I was brand new to all these libraries and wanted to ensure I was getting the code right.

In these early tests, I honestly did not expect `retrieval` (pure Elixir code that hasn't been touched in ten years) to beat `trie_hard` (Rust code from just ten months ago) on execution time.  I initially assumed this is because I have a fairly small set of commands, and a larger trie might give `trie_hard` the advantage.  But I found the exact opposite: As I started adding random words to the trie, `trie_hard`'s relative performance dropped, eventually placing it on the bottom below both of the Elixir-native libraries.

It was at this point that I added the ETS approach.  I had used an ETS for partial matches [in ExMUSH](https://github.com/wisq/ex_mush/blob/5738cce4462dba5ebc1b8305dfc1d75582d72c31/lib/ex_mush/world/object_directory.ex#L57) to index and lookup players by name.  At the time, it seemed like a neat way to use ETSes to do a partial match, but I assumed a proper trie would be faster.  Still, for completeness, I figured I should add my ETS approach to the benchmark, if only to see how much faster the trie approach was.

And this was where the real shocker happened: The ETS approach was immediately and decisively beating all of the other approaches — and its advantage actually grew larger with trie size.  This was especially surprising because ETS `ordered_set` isn't technically a trie at all, but rather, a binary search tree (BST) based on Erlang term order.

For the sake of completeness, I continued to expand the scenarios, adding variations and adjustments that would better match how I might use the library, or that would demonstrate the strengths or weaknesses of the various libraries.

In these variations, the three libraries jockeyed for position.  The pure Elixir libraries (`dimi_trie`, Retrieval) usually had fairly similar performance, and TrieHard tended to do better when it could benefit from a low partial match limit.  Meanwhile, in each and every scenario, the ETS approach came out on top.

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

This library also spent most of its time around the bottom of the performance charts, with one major exception — in the V1 case with 100k commands, all matches, and no filtering, it actually outperformed everything except ETS.  (Granted, ETS still outperformed it by more than 5x.)
