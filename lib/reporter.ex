defmodule BencheeAsync.Reporter do
  @moduledoc """
  The GenServer responsible for tracking units of work done.

  To allow for more flexibility, this GenServer must be started manually before beginning the benchmarking as part of the benchmark suite setup.

  ```elixir
  # in an .exs script
  #{__MODULE__}.start_link()

  # in an ExUnit test
  start_supervised!(#{__MODULE__})
  ```

  ### Reporting
  To report a unit of work done, execute `#{__MODULE__}.report/0` anywhere within your application code.

  To avoid introducing dev-specific logic into your application code, it is advised to use a mocking library to mock your internal functions. [:meck](https://github.com/eproxus/meck) or [Mimic](https://github.com/edgurgel/mimic) will both work, the choice between either or otherwise would be a matter of taste.

  For example, with Mimic:
  ```
  # test/test_helper.exs
  Mimic.copy(MyApp)
  ExUnit.start()
  ```

  ```
  # test/my_app_test.exs
  defmodule MyAppTest do
    use ExUnit.Case, async: false
    use Mimic

    @tag :benchmark
    test "benchmarking async work!" do
      MyApp
      |> stub(:do_work, fn _arg ->
        #{__MODULE__}.report()
        :ok
      end)

      # benchmarking code goes here...
      BencheeAsync.run(%{....})
    end
  end
  ```

  """
  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl GenServer
  def init(_opts \\ []) do
    {:ok, init_state()}
  end

  @doc false
  def reset_timer() do
    GenServer.cast(__MODULE__, :reset_timer)
  end

  @doc false
  def maybe_enable() do
    GenServer.cast(__MODULE__, :maybe_enable)
  end

  @doc false
  def disable() do
    GenServer.call(__MODULE__, :disable)
  end

  @doc false
  def ignore_ms(ms) when is_number(ms) do
    GenServer.call(__MODULE__, {:ignore_ms, ms})
  end

  @doc false
  def set_scenario(scenario_name, input \\ :__no_input) when is_binary(scenario_name) do
    GenServer.cast(__MODULE__, {:set_scenario, scenario_name, :erlang.phash2(input)})
  end

  @doc """
  Records a unit of work done. Should be called each time a unit of work is performed.

  It is advised to mock the function that you wish to track and call this function within the mock.
  """
  @spec record() :: :ok
  def record(n \\ 1) do
    GenServer.cast(__MODULE__, {:record, n})
  end

  @doc """
  Retrieves the samples recorded for a given scenario and input combination.
  """
  @spec get_samples(String.t(), term() | :__no_input) :: [integer()]
  def get_samples(scenario_name, input \\ :__no_input) when is_binary(scenario_name) do
    GenServer.call(__MODULE__, {:samples, scenario_name, :erlang.phash2(input)})
  end

  @doc """
  Resets the state within the Reporter. This is not called automatically after the benchmark is run, as it is expected that the Reporter process terminates after each benchmark run.

  If this is not the case for you, you can run this manually between benchmark runs as so:

  ```elixir
  BencheeAsync.run(%{...})
  BencheeAsync.Reporter.clear()
  BencheeAsync.run(%{...})
  ```

  If the scenario names are different between each benchmark run, then clearing the state would not be necessary.
  """
  @spec clear() :: :ok
  def clear() do
    GenServer.call(__MODULE__, :clear)
  end

  # GenServer
  @impl GenServer
  def handle_call({:set_pid, pid}, _caller, state) when is_pid(pid) do
    {:reply, :ok, %{state | current_pid: pid}}
  end

  @impl GenServer
  def handle_call({:samples, scenario_name, hash}, _caller, state) do
    {:reply, Map.get(state.samples, {scenario_name, hash}, []), state}
  end

  @impl GenServer
  def handle_call(:clear, _caller, _state) do
    {:reply, :ok, init_state()}
  end

  @impl GenServer
  def handle_call({:ignore_ms, ms}, _caller, state) do
    Process.send_after(self(), :clear_ignore, round(ms))
    {:reply, :ok, %{state | ignoring?: true, ignore_until: current_time() + round(ms * 1000)}}
  end

  @impl GenServer
  def handle_call(:disable, _caller, state) do
    {:reply, :ok, %{state | ignoring?: true}}
  end

  @impl GenServer
  def handle_info(:clear_ignore, state) do
    {:noreply, %{state | start_time: current_time(), ignoring?: false, ignore_until: nil}}
  end

  @impl GenServer
  def handle_cast(:maybe_enable, %{ignoring?: true, ignore_until: nil} = state) do
    {:noreply, %{state | ignoring?: false, start_time: current_time()}}
  end

  # keep ignoring
  @impl GenServer
  def handle_cast(:maybe_enable, state) do
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:record, _}, %{ignoring?: true} = state),
    do: {:noreply, state}

  @impl GenServer
  def handle_cast({:record, n}, state) do
    now = current_time()
    diff = now - state.start_time

    samples =
      Map.update(state.samples, state.current_key, [diff], fn prev ->
        List.duplicate(diff, n) ++ prev
      end)

    {:noreply, %{state | samples: samples, start_time: now}}
  end

  @impl GenServer
  def handle_cast(:reset_timer, state) do
    {:noreply, %{state | start_time: current_time()}}
  end

  @impl GenServer
  def handle_cast({:set_scenario, scenario_name, hash}, state) do
    {:noreply, %{state | current_key: {scenario_name, hash}}}
  end

  defp current_time, do: :erlang.system_time(:nano_seconds)

  defp init_state do
    %{
      start_time: current_time(),
      samples: %{},
      current_key: nil,
      ignoring?: false,
      ignore_until: nil
    }
  end
end
