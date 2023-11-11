defmodule BencheeAsync.Reporter do
  @moduledoc false
  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl GenServer
  def init(_opts \\ []) do
    {:ok, init_state()}
  end

  def reset_timer() do
    GenServer.cast(__MODULE__, :reset_timer)
  end

  def maybe_enable() do
    GenServer.cast(__MODULE__, :maybe_enable)
  end

  def disable() do
    GenServer.call(__MODULE__, :disable)
  end

  def ignore_ms(ms) when is_number(ms) do
    GenServer.call(__MODULE__, {:ignore_ms, ms})
  end

  def record(scenario_name) do
    GenServer.cast(__MODULE__, {:record, scenario_name})
  end

  def get_samples(scenario_name) do
    GenServer.call(__MODULE__, {:samples, scenario_name})
  end

  def clear() do
    GenServer.call(__MODULE__, :clear)
  end

  @impl GenServer
  def handle_call({:set_pid, pid}, _caller, state) when is_pid(pid) do
    {:reply, :ok, %{state | current_pid: pid}}
  end

  @impl GenServer
  def handle_call({:samples, scenario_name}, _caller, state) do
    {:reply, Map.get(state.samples, scenario_name, []), state}
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
  def handle_cast({:record, _scenario_name}, %{ignoring?: true} = state),
    do: {:noreply, state}

  @impl GenServer
  def handle_cast({:record, scenario_name}, state) do
    now = current_time()
    diff = now - state.start_time

    samples =
      Map.update(state.samples, scenario_name, [diff], fn prev ->
        [diff | prev]
      end)

    {:noreply, %{state | samples: samples, start_time: now}}
  end

  @impl GenServer
  def handle_cast(:reset_timer, state) do
    {:noreply, %{state | start_time: current_time()}}
  end

  defp current_time, do: :erlang.system_time(:nano_seconds)

  defp init_state do
    %{start_time: current_time(), samples: %{}, ignoring?: false, ignore_until: nil}
  end
end
