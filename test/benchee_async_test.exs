defmodule BencheeAsyncTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO
  alias BencheeAsync.Reporter

  setup do
    Application.put_env(:elixir, :ansi_enabled, false)
    :ok
  end

  test "compat" do
    start_supervised!(Reporter)

    assert %Benchee.Suite{} =
             BencheeAsync.run(
               %{
                 "case_10_numbers" => fn ->
                   Task.start(fn ->
                     :timer.sleep(500)
                     Reporter.record("case_10_numbers")
                     # Reporter.record()
                   end)

                   :timer.sleep(500)
                 end
               },
               time: 0,
               warmup: 0
             )
  end

  test "record async work in benchmark function" do
    start_supervised!(Reporter)

    io =
      capture_io(fn ->
        BencheeAsync.run(
          %{
            "case_10_numbers" => fn ->
              Task.start(fn ->
                :timer.sleep(500)
                Reporter.record("case_10_numbers")
              end)

              :timer.sleep(500)
            end
          },
          # inputs: %{
          #   "Small" => Enum.to_list(1..1_000),
          #   "Medium" => Enum.to_list(1..10_000),
          #   "Bigger" => Enum.to_list(1..100_000)
          # },
          time: 1,
          warmup: 0
        )
      end)

    assert io =~ "1 s"
    assert io =~ " 1 "
  end

  test "ignores reports during warmup time" do
    start_supervised!(Reporter)

    io =
      capture_io(fn ->
        BencheeAsync.run(
          %{
            "case_10_numbers" => fn ->
              Task.start(fn ->
                :timer.sleep(100)
                Reporter.record("case_10_numbers")
                # Reporter.record()
              end)

              assert Reporter.get_samples("case_10_numbers") |> length() < 3

              :timer.sleep(2500)
            end,
            "case_100_numbers" => fn ->
              Task.start(fn ->
                :timer.sleep(1000)
                Reporter.record("case_100_numbers")
                # Reporter.record()
              end)

              assert Reporter.get_samples("case_10_numbers") |> length() < 3

              :timer.sleep(1500)
            end
          },
          time: 1,
          warmup: 3,
          formatters: [{Benchee.Formatters.Console, extended_statistics: true}]
        )
      end)

    IO.puts(io)
    assert io =~ inspect(Reporter.get_samples("case_10_numbers") |> length())
    assert io =~ inspect(Reporter.get_samples("case_100_numbers") |> length())
  end
end
