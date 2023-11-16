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
                     Reporter.record()
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
                Reporter.record()
              end)

              :timer.sleep(500)
            end
          },
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
                Reporter.record()
              end)

              assert Reporter.get_samples("case_10_numbers") |> length() < 3

              :timer.sleep(2500)
            end,
            "case_100_numbers" => fn ->
              Task.start(fn ->
                :timer.sleep(1000)
                Reporter.record()
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

    assert io =~ inspect(Reporter.get_samples("case_10_numbers") |> length())
    assert io =~ inspect(Reporter.get_samples("case_100_numbers") |> length())
  end

  test "with inputs" do
    start_supervised!(Reporter)

    io =
      capture_io(fn ->
        BencheeAsync.run(
          %{
            "case_faster" => fn input ->
              Task.start(fn ->
                :timer.sleep(input)
                Reporter.record()
              end)

              :timer.sleep(input)
            end,
            "case_slower" => fn input ->
              Task.start(fn ->
                :timer.sleep(input)
                Reporter.record(4)
              end)

              :timer.sleep(input * 2)
            end
          },
          time: 3,
          warmup: 0,
          inputs: %{
            "Small" => 10,
            "Medium" => 50,
            "Bigger" => 75
          },
          formatters: [{Benchee.Formatters.Console, extended_statistics: true}]
        )
      end)

    assert io =~ inspect(Reporter.get_samples("case_faster", 10) |> length())
    assert io =~ inspect(Reporter.get_samples("case_faster", 50) |> length())
    assert io =~ inspect(Reporter.get_samples("case_faster", 75) |> length())
    assert io =~ inspect(Reporter.get_samples("case_slower", 10) |> length())
    assert io =~ inspect(Reporter.get_samples("case_slower", 50) |> length())
    assert io =~ inspect(Reporter.get_samples("case_slower", 75) |> length())
  end
end
