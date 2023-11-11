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

The following must be performed in order to use this library:

1. Start the `BencheeAsync.Reporter` GenServer.
2. Benchmark functions must call `BencheeAsync.Reporter.record/1` with the scenario name.
3. Set the `extended_statistics: true` option for `Benchee.Formatters.Console`

### Example

This shows an example of running Benchee from within a ExUnit test suite.

```elixir
defmodule BencheeAsyncTest do
  use ExUnit.Case, async: false
  
  test "measure async work!" do
    start_supervised!(BencheeAsync.Reporter)

    BencheeAsync.run(
      %{
        "case_100_ms" => fn ->
          Task.start(fn ->
            :timer.sleep(100)
            BencheeAsync.Reporter.record("case_100_ms")
          end)
          :timer.sleep(2500)
        end,
        "case_1000_ms" => fn ->
          Task.start(fn ->
            :timer.sleep(1000)
            BencheeAsync.Reporter.record("case_1000_ms")
          end)
          :timer.sleep(1500)
        end
      },
      time: 1,
      warmup: 3,
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

### Usage in a Real World Application

It is advised to mock your async functions using [`:meck`](https://hexdocs.pm/meck/meck.html) or [`Mimic`](https://hexdocs.pm/mimic/Mimic.html). The mocked function would be where you trigger the reporting to the scenario that you are measuring.

At the moment, hardcoding of the scenario name argument is required.

### Internals and Behavior

This library injects hooks into the `Benchee.run/1` in order to achieve async work benchmarking.

`BencheeAsync` utilizes the `Benchee` public APIs only to achieve the hook injections. All user provided hooks will be executed **after** the injected hooks.

Global hooks need to be injected in order to initiate tracking of post warmup timing and post-scenario timings.

### Limitations

- The `memory_time` will extend the execution, hence the sample size will include counts during this time.
