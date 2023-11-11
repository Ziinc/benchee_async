# BencheeAsync

Async work `Benchee` plugin for benchmarking multi-process performance.

Often, one needs to optimize certain parts of a system that are spread out over multiple processes, pipelines, gen_stages, etc. However, Benchee only allows us to benchmark and measure the performance of a singular function within a singular executing process. It cannot keept track cross-process work performed. This plugin allows us to measure async units of work done, thereby allowing us to optimize our async pipelines.

## Installation

```elixir
def deps do
  [
    {:benchee, "~> 1.0", only: [:dev, :test]},
    {:benchee_async, "~> 0.1.0", only: [:dev, :test]}
  ]
end
```

## Usage
The goal of this library is to be able to **approximately** track the amount of work done, rate of async work completion, as well as time taken to accomplish said async work.

The following **must be configured**:

1. Start the `BencheeAsync.Reporter` GenServer.
2. Benchmark functions must call `BencheeAsync.Reporter.record/0` to record a unit of work completed.
3. Set the `extended_statistics: true` option for `Benchee.Formatters.Console`

### Example

This shows an example of running Benchee from within a ExUnit test suite.

```elixir
defmodule MyAppTest do
  use ExUnit.Case, async: false
  
  test "measure async work!" do
    # start the reporter process
    start_supervised!(BencheeAsync.Reporter)

    # use BencheeAsync instead of Benchee
    BencheeAsync.run(
      %{
        "case_100_ms" => fn ->
          Task.start(fn ->
            :timer.sleep(100)
            BencheeAsync.Reporter.record()
          end)
          :timer.sleep(2500)
        end,
        "case_1000_ms" => fn ->
          Task.start(fn ->
            :timer.sleep(1000)
            BencheeAsync.Reporter.record()
          end)
          :timer.sleep(1500)
        end
      },
      time: 1,
      warmup: 3,
      # use extended_statistics to view units of work done
      formatters: [{Benchee.Formatters.Console, extended_statistics: true}]
    )
  end
end
```

The resulting console output will be as follows:

```
Operating System: macOS
CPU Information: Apple M1 Pro
Number of Available Cores: 10
Available memory: 32 GB
Elixir 1.15.5
Erlang 26.1.2

Benchmark suite executing with the following configuration:
warmup: 3 s
time: 1 s
memory time: 0 ns
reduction time: 0 ns
parallel: 1
inputs: none specified
Estimated total run time: 8 s

Benchmarking case_1000_ms ...
Benchmarking case_100_ms ...

Name                       ips        average  deviation         median         99th %
case_100_ms           9.92        0.101 s     ±0.20%        0.101 s        0.101 s
case_1000_ms          1.00         1.00 s     ±0.04%         1.00 s         1.00 s

Comparison:
case_100_ms           9.92
case_1000_ms          1.00 - 9.93x slower +0.90 s

Extended statistics:

Name                     minimum        maximum    sample size                     mode
case_100_ms          0.101 s        0.101 s              3                     None
case_1000_ms          1.00 s         1.00 s              1                     None
```

Interpretation differences from `Benchee` are as follows:

- `ips`: The maximum iterations per second of the async process(es) if the async logic was repeatedly executed in isolation.
- `average`, `deviation`, `median`, `99th %`: The statistics of execution time between each reported unit work done.
- `sample size`: The amount of reported units of work done, which will correspond to the number of `BencheeAsync.Reporter.report/1` calls.


### Usage with Inputs

Inputs work as well with no additional configuration needed.

```
Operating System: macOS
CPU Information: Apple M1 Pro
Number of Available Cores: 10
Available memory: 32 GB
Elixir 1.15.5
Erlang 26.1.2

Benchmark suite executing with the following configuration:
warmup: 0 ns
time: 3 s
memory time: 0 ns
reduction time: 0 ns
parallel: 1
inputs: Bigger, Medium, Small
Estimated total run time: 18 s

Benchmarking case_faster with input Bigger ...
Benchmarking case_faster with input Medium ...
Benchmarking case_faster with input Small ...
Benchmarking case_slower with input Bigger ...
Benchmarking case_slower with input Medium ...
Benchmarking case_slower with input Small ...

##### With input Bigger #####
Name                  ips        average  deviation         median         99th %
case_faster        1.08 M     0.00092 ms    ±36.87%     0.00092 ms     0.00154 ms
case_slower     0.00001 M       75.90 ms     ±0.22%       75.94 ms       76.03 ms

Comparison: 
case_faster        1.08 M
case_slower     0.00001 M - 82215.44x slower +75.90 ms

Extended statistics: 

Name                minimum        maximum    sample size                     mode
case_faster      0.00013 ms     0.00154 ms             39               0.00088 ms
case_slower        75.27 ms       76.03 ms             20                     None

##### With input Medium #####
Name                  ips        average  deviation         median         99th %
case_faster      982.25 K     0.00102 ms   ±151.32%     0.00083 ms      0.0123 ms
case_slower      0.0196 K       51.04 ms     ±0.76%       51.00 ms       52.96 ms

Comparison: 
case_faster      982.25 K
case_slower      0.0196 K - 50138.38x slower +51.04 ms

Extended statistics: 

Name                minimum        maximum    sample size                     mode
case_faster      0.00013 ms      0.0123 ms             58               0.00075 ms
case_slower        50.49 ms       52.96 ms             30                     None

##### With input Small #####
Name                  ips        average  deviation         median         99th %
case_faster        1.68 M     0.00059 ms    ±38.29%     0.00058 ms     0.00108 ms
case_slower     0.00009 M       11.00 ms     ±1.08%       11.01 ms       11.61 ms

Comparison: 
case_faster        1.68 M
case_slower     0.00009 M - 18489.07x slower +11.00 ms

Extended statistics: 

Name                minimum        maximum    sample size                     mode
case_faster      0.00013 ms     0.00275 ms            272               0.00063 ms
case_slower        10.44 ms       11.69 ms            14311.02 ms, 11.04 ms, 11.01
```

### Usage in a Real World Application

It is advised to mock your async functions using [`:meck`](https://hexdocs.pm/meck/meck.html) or [`Mimic`](https://hexdocs.pm/mimic/Mimic.html). The mocked function would be where you trigger the reporting to the scenario that you are measuring.

At the moment, hardcoding of the scenario name argument is required.

### Internals and Behavior

This library injects hooks into the `Benchee.run/1` in order to achieve async work benchmarking.

`BencheeAsync` utilizes the `Benchee` public APIs only to achieve the hook injections. All user provided hooks will be executed **after** the injected hooks.

Global hooks need to be injected in order to initiate tracking of post warmup timing and post-scenario timings.

To allow `BencheeAsync.Reporter.record/0` to work without specifying scenario name or input name, the input is used in the local `:before_scenario` hook in order to identify the scenario-input combination being benchmarked. The input is then hashed using `:erlang.phash2/2` for internal referencing.

### Limitations

- The `memory_time` will extend the execution, hence the sample size will include counts during this time.
