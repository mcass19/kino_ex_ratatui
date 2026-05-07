defmodule Kino.ExRatatui.PropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias KinoExRatatui.Test.Counter

  setup :configure_livebook_bridge

  # Same lists Kino.ExRatatui itself uses internally — kept here to
  # let the properties exercise every reserved key. If a future PR
  # adds a new display option, dropping it into this list extends the
  # round-trip / strip-out coverage automatically.
  @display_keys [
    :theme,
    :font_family,
    :font_size,
    :height,
    :cursor_blink,
    :scrollback,
    :stopped_message
  ]

  @reserved_keys @display_keys ++ [:mod, :name, :transport]

  defp configure_livebook_bridge(_) do
    Kino.Test.configure_livebook_bridge(%{})
    :ok
  end

  describe "new/2 — display option round-trip" do
    property "every valid display value lands in display map unchanged" do
      check all(
              key <- StreamData.member_of(@display_keys),
              value <- valid_display_value(key)
            ) do
        with_kino([{key, value}], fn kino ->
          assert :sys.get_state(kino.pid).ctx.assigns.display[key] == value
        end)
      end
    end

    property "atom theme shorthands :dark / :light / :livebook are preserved" do
      check all(atom <- StreamData.member_of([:dark, :light, :livebook])) do
        with_kino([theme: atom], fn kino ->
          assert :sys.get_state(kino.pid).ctx.assigns.display.theme == atom
        end)
      end
    end

    property "unset keys fall through to the module default" do
      # Setting only one display key shouldn't change any other. Pick
      # any single key, set it to a valid value, and assert the
      # other six come from the module-default map.
      defaults = default_display()

      check all(
              key <- StreamData.member_of(@display_keys),
              value <- valid_display_value(key)
            ) do
        with_kino([{key, value}], fn kino ->
          display = :sys.get_state(kino.pid).ctx.assigns.display

          for other <- @display_keys -- [key] do
            assert display[other] == defaults[other],
                   "untouched key #{inspect(other)} drifted from default"
          end
        end)
      end
    end
  end

  describe "new/2 — mount opts strip" do
    property "reserved keys never appear in mount_opts after new/2" do
      check all(opts <- mixed_opts()) do
        with_kino(opts, fn kino ->
          mount_opts = :sys.get_state(kino.pid).ctx.assigns.mount_opts

          for key <- @reserved_keys do
            refute Keyword.has_key?(mount_opts, key),
                   "reserved key #{inspect(key)} leaked into mount_opts: #{inspect(mount_opts)}"
          end
        end)
      end
    end

    property "non-reserved keys are preserved in mount_opts in original order" do
      check all(opts <- mixed_opts()) do
        with_kino(opts, fn kino ->
          mount_opts = :sys.get_state(kino.pid).ctx.assigns.mount_opts
          expected = Enum.reject(opts, fn {k, _} -> k in @reserved_keys end)

          assert mount_opts == expected
        end)
      end
    end
  end

  describe "frame/2 — option validation" do
    property "unknown opts always raise ArgumentError naming the key" do
      reserved_or_supported = [:cols, :rows, :theme, :font_family, :font_size]

      check all(
              key <- non_reserved_atom_excluding(reserved_or_supported),
              value <- any_value()
            ) do
        widgets = [
          {%ExRatatui.Widgets.Paragraph{text: "x"},
           %ExRatatui.Layout.Rect{x: 0, y: 0, width: 5, height: 1}}
        ]

        assert_raise ArgumentError, ~r/unknown option/, fn ->
          Kino.ExRatatui.frame(widgets, [{key, value}])
        end
      end
    end
  end

  ## Helpers

  defp with_kino(opts, fun) do
    kino = Kino.ExRatatui.new(Counter, opts)

    try do
      fun.(kino)
    after
      if Process.alive?(kino.pid), do: GenServer.stop(kino.pid, :shutdown)
    end
  end

  # Mirrors `@default_display` in `lib/kino/ex_ratatui.ex`. Duplicated
  # here so a stale assertion fails loudly rather than silently
  # tracking module changes; if this list drifts, the round-trip
  # property catches it on the next CI run.
  defp default_display do
    %{
      theme: %{background: "#1e1e2e", foreground: "#cdd6f4", cursor: "#f5e0dc"},
      font_family: "ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace",
      font_size: 13,
      height: "400px",
      cursor_blink: true,
      scrollback: 1000,
      stopped_message: "App stopped — re-evaluate the cell to start a new run."
    }
  end

  defp valid_display_value(:theme), do: theme_value()
  defp valid_display_value(:font_family), do: non_empty_string()
  defp valid_display_value(:font_size), do: StreamData.positive_integer()
  defp valid_display_value(:height), do: non_empty_string()
  defp valid_display_value(:cursor_blink), do: StreamData.boolean()
  defp valid_display_value(:scrollback), do: StreamData.integer(0..10_000)
  defp valid_display_value(:stopped_message), do: StreamData.string(:printable)

  defp theme_value do
    StreamData.one_of([
      StreamData.constant(:dark),
      StreamData.constant(:light),
      StreamData.constant(:livebook),
      theme_map()
    ])
  end

  defp theme_map do
    StreamData.map_of(
      StreamData.atom(:alphanumeric),
      non_empty_string(),
      max_length: 6
    )
  end

  defp non_empty_string do
    StreamData.string(:printable, min_length: 1, max_length: 32)
  end

  # Generator for arbitrary mount-opt-like keyword lists with at most
  # 8 entries, mixing valid display pairs and random non-reserved
  # pairs. `uniq_list_of` (with `uniq_fun: &elem(&1, 0)`) keeps key
  # uniqueness so `Keyword.has_key?` assertions are unambiguous.
  defp mixed_opts do
    StreamData.uniq_list_of(
      StreamData.one_of([display_pair(), random_pair()]),
      uniq_fun: &elem(&1, 0),
      max_length: 8
    )
  end

  defp display_pair do
    StreamData.bind(StreamData.member_of(@display_keys), fn key ->
      StreamData.bind(valid_display_value(key), fn value ->
        StreamData.constant({key, value})
      end)
    end)
  end

  defp random_pair do
    StreamData.bind(non_reserved_atom(), fn key ->
      StreamData.bind(any_value(), fn value ->
        StreamData.constant({key, value})
      end)
    end)
  end

  defp non_reserved_atom do
    non_reserved_atom_excluding(@reserved_keys)
  end

  defp non_reserved_atom_excluding(excluded) do
    StreamData.atom(:alphanumeric)
    |> StreamData.filter(fn a -> a not in excluded end)
  end

  defp any_value do
    StreamData.one_of([
      StreamData.integer(),
      StreamData.boolean(),
      StreamData.string(:printable),
      StreamData.constant(nil)
    ])
  end
end
