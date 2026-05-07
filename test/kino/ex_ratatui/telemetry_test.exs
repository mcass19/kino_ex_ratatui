defmodule Kino.ExRatatui.TelemetryTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Kino.ExRatatui.Telemetry

  doctest Telemetry

  describe "span/3" do
    test "wraps the function in :start / :stop events under [:kino_ex_ratatui | event]" do
      attach([
        [:kino_ex_ratatui, :demo, :span, :start],
        [:kino_ex_ratatui, :demo, :span, :stop]
      ])

      result =
        Telemetry.span([:demo, :span], %{tag: :demo}, fn -> :hello end)

      assert result == :hello

      assert_receive {:event, [:kino_ex_ratatui, :demo, :span, :start], start_meas, %{tag: :demo}}

      assert is_integer(start_meas[:monotonic_time])
      assert is_integer(start_meas[:system_time])

      assert_receive {:event, [:kino_ex_ratatui, :demo, :span, :stop], stop_meas, %{tag: :demo}}

      assert is_integer(stop_meas[:duration])
    end

    test "fires :exception when the function raises and re-raises the original error" do
      attach([[:kino_ex_ratatui, :demo, :span, :exception]])

      assert_raise RuntimeError, "boom", fn ->
        Telemetry.span([:demo, :span], %{}, fn -> raise "boom" end)
      end

      assert_receive {:event, [:kino_ex_ratatui, :demo, :span, :exception], _measurements,
                      metadata}

      assert metadata.kind == :error
      assert is_struct(metadata.reason, RuntimeError)
      assert is_list(metadata.stacktrace)
    end
  end

  describe "execute/3" do
    test "emits a single event under [:kino_ex_ratatui | event]" do
      attach([[:kino_ex_ratatui, :demo, :one_off]])

      :ok = Telemetry.execute([:demo, :one_off], %{}, %{tag: :demo})

      assert_receive {:event, [:kino_ex_ratatui, :demo, :one_off], measurements, %{tag: :demo}}

      assert is_integer(measurements[:system_time])
    end

    test "preserves caller-supplied :system_time instead of overwriting it" do
      attach([[:kino_ex_ratatui, :demo, :one_off]])

      :ok = Telemetry.execute([:demo, :one_off], %{system_time: 42}, %{})

      assert_receive {:event, [:kino_ex_ratatui, :demo, :one_off], %{system_time: 42}, _meta}
    end
  end

  describe "attach_default_logger/1 + detach_default_logger/0" do
    test "logs every default event at the configured level" do
      :ok = Telemetry.attach_default_logger(level: :info)

      log =
        capture_log(fn ->
          Telemetry.execute([:input, :forward], %{}, %{mod: __MODULE__, byte_count: 1})
        end)

      assert log =~ "[kino_ex_ratatui]"
      assert log =~ "kino_ex_ratatui.input.forward"
      assert log =~ inspect(__MODULE__)
    after
      _ = Telemetry.detach_default_logger()
    end

    test "honours a custom :events override" do
      events = [[:kino_ex_ratatui, :resize]]
      :ok = Telemetry.attach_default_logger(level: :debug, events: events)

      assert :telemetry.list_handlers([:kino_ex_ratatui, :resize]) != []
    after
      _ = Telemetry.detach_default_logger()
    end

    test "attaching twice returns {:error, :already_exists}" do
      :ok = Telemetry.attach_default_logger()
      assert {:error, :already_exists} = Telemetry.attach_default_logger()
    after
      _ = Telemetry.detach_default_logger()
    end

    test "detach without prior attach returns {:error, :not_found}" do
      assert {:error, :not_found} = Telemetry.detach_default_logger()
    end
  end

  defp attach(events) do
    handler_id = "telemetry-test-#{System.unique_integer([:positive])}"

    :ok = :telemetry.attach_many(handler_id, events, &__MODULE__.__forward__/4, self())

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  @doc false
  def __forward__(event, measurements, metadata, parent) do
    send(parent, {:event, event, measurements, metadata})
  end
end
