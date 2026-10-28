defmodule World.Clock do
  @moduledoc """
  The clock of the world (`docs/world.md`, "Time"). The time of the world
  comes from the wall clock: its start, plus `scale` times the wall time
  since its start. One second of the wall clock is one day of the world
  (a scale of 86,400).

  The times are integers in milliseconds: `start` and the wall times are
  wall clock times (Unix, UTC); a world time counts from the start of the
  world.
  """

  @scale 86_400
  @day 86_400_000

  defstruct start: 0, scale: @scale

  @doc "The default scale: world seconds for each second of the wall clock."
  def scale, do: @scale

  @doc """
  A clock. The options: `start` (the wall time of the start of the
  world, now by default) and `scale` (86,400 by default).
  """
  def new(opts \\ []) do
    scale = Keyword.get(opts, :scale, @scale)
    unless is_integer(scale) and scale > 0, do: raise(ArgumentError, "the scale of a clock is a positive integer")
    %__MODULE__{start: Keyword.get_lazy(opts, :start, &wall/0), scale: scale}
  end

  @doc "The wall time now, in milliseconds."
  def wall, do: System.os_time(:millisecond)

  @doc "The world time at a wall time (now by default)."
  def at(%__MODULE__{start: start, scale: scale}, wall \\ wall()), do: (wall - start) * scale

  @doc "The world time of a wall time span: the time of a task of code."
  def to_world(%__MODULE__{scale: scale}, wall_ms), do: wall_ms * scale

  @doc "The wall time span of a world time span, rounded up: the wait for a drive or a walk."
  def to_wall(%__MODULE__{scale: scale}, world_ms), do: div(world_ms + scale - 1, scale)

  @doc ~S'A world time as people read it: `"day 412, 14:05"`. The first day is day 1.'
  def label(world_ms) when is_integer(world_ms) and world_ms >= 0 do
    minutes = div(rem(world_ms, @day), 60_000)
    pad = &String.pad_leading(Integer.to_string(&1), 2, "0")
    "day #{div(world_ms, @day) + 1}, #{pad.(div(minutes, 60))}:#{pad.(rem(minutes, 60))}"
  end
end
