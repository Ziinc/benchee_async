defmodule BencheeAsync do
  @moduledoc """
  Documentation for `BencheeAsync`.
  """
  alias BencheeAsync.Reporter

  @doc """
  Runs the benchmark jobs as per the Benchee-compatible configuration.

  Full list of configuration can be found in the [documentation for Benchee](https://hexdocs.pm/benchee/readme.html#configuration).

  ### Internals
  This function will inject Reporter lifecycle hooks into each bencahmark job. These hooks will be executed **before** the user provided hooks.
  The only exception to this is where the timer reset is performed after the user's `:before_each` global hook is run.

  The `BencheeAsync.Reporter` will immediately start tracking work completion on warmup end, and on job completion (where the `:after_scenario` hook is run).
  This means that any configuration option that extends measurement times (such as `:memory_time`) will result in tracking occuring beyond the `:time` configured.
  """
  @spec run(map(), keyword()) :: Benchee.Suite.t()
  def run(config, opts \\ []) do
    Reporter.clear()
    user_bef_scenario_hook = Keyword.get(opts, :before_scenario)
    user_aft_scenario_hook = Keyword.get(opts, :after_scenario)
    user_bef_each = Keyword.get(opts, :before_each)

    # inject our own reporting hooks
    opts =
      opts
      |> Keyword.put(:before_each, fn input ->
        Reporter.maybe_enable()

        new_input =
          if user_bef_each != nil do
            user_bef_each.(input)
          else
            input
          end

        Reporter.reset_timer()
        new_input
      end)
      |> Keyword.put(:before_scenario, fn input ->
        if user_bef_scenario_hook != nil do
          user_bef_scenario_hook.(input)
        else
          input
        end
      end)
      |> Keyword.put(:after_scenario, fn input ->
        Reporter.disable()

        if user_aft_scenario_hook != nil do
          user_aft_scenario_hook.(input)
        else
          input
        end
      end)

    suite =
      opts
      |> Benchee.init()
      |> Benchee.system()
      |> then(fn suite ->
        Enum.reduce(config, suite, fn
          {k, func}, acc when is_function(func) ->
            before_scenario = fn input ->
              Reporter.set_scenario(k, input)
              input
            end

            Benchee.benchmark(acc, k, {func, before_scenario: before_scenario})

          {k, {func, opts}}, acc ->
            user_local_bef_scenario = Keyword.get(opts, :before_scenario)

            opts =
              Keyword.put(opts, :before_scenario, fn input ->
                Reporter.set_scenario(k, input)

                if user_local_bef_scenario != nil do
                  user_local_bef_scenario.(input)
                else
                  input
                end
              end)

            Benchee.benchmark(acc, k, {func, opts})
        end)
      end)
      |> then(fn suite ->
        # ignore warmup timings
        if suite.configuration.warmup > 0 do
          Reporter.ignore_ms(suite.configuration.warmup / (1000 * 1000))
        end

        suite
      end)
      |> Benchee.collect()
      |> then(fn suite ->
        updated_scenarios =
          for scenario <- suite.scenarios,
              run_time_data = scenario.run_time_data do
            samples = Reporter.get_samples(scenario.name, scenario.input)

            %{scenario | run_time_data: Map.put(run_time_data, :samples, samples)}
          end

        %{suite | scenarios: updated_scenarios}
      end)
      |> Benchee.statistics()
      |> Benchee.relative_statistics()
      |> Benchee.Formatter.output()

    suite
  end
end
