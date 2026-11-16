defmodule World.Detail do
  @moduledoc """
  The level of detail while a model is made: `:near`, `:mid` or `:far`.
  The shapes read it. At `:mid` a round shape has half of its sides and
  one smooth step less; at `:far` a quarter of its sides and no smooth
  step. So `mix world.build` makes each model once for each level.
  """

  @factor %{near: 1.0, mid: 0.5, far: 0.25}

  @doc "Make a model with `fun` at a level."
  def with(level, fun) when is_map_key(@factor, level) do
    old = Process.put(:world_detail, level)

    try do
      fun.()
    after
      if old, do: Process.put(:world_detail, old), else: Process.delete(:world_detail)
    end
  end

  @doc """
  `value`, after a full garbage collection of the process. The VM at the
  edge has 128 MB, and a build makes much garbage: the collector keeps
  it in the old heap until a full sweep, and a full sweep copies the
  live data to a new heap, so the peak is some times the live data. A
  big step of a build (a mesh of a person, a primitive of a GLB) calls
  this at its end, when little is live: the peak of the near level of a
  person goes from 132 MB to less (`docs/factory.md`). In `lean(false,
  fun)` there is no collection: the people of a construction with no
  limit of memory do not wait for it.
  """
  def collect(value) do
    if Process.get(:world_lean, true), do: :erlang.garbage_collect()
    value
  end

  @doc "Run `fun` with (`true`, the default) or with no collection after each big step (`collect/1`)."
  def lean(lean, fun) do
    old = Process.put(:world_lean, lean)

    try do
      fun.()
    after
      if old == nil, do: Process.delete(:world_lean), else: Process.put(:world_lean, old)
    end
  end

  @doc "The level now (`:near` by default)."
  def level, do: Process.get(:world_detail, :near)

  @doc "The number of sides of a round shape at the level now: never less than `min(n, 6)`."
  def sides(n), do: max(round(n * @factor[level()]), min(n, 6))

  @doc "A step along a shape (a distance between two sections) at the level now: longer at `:mid` and `:far`."
  def step(d), do: d / @factor[level()]

  @doc "The smooth steps of a shape at the level now."
  def smooth(n) do
    case level() do
      :near -> n
      :mid -> max(n - 1, 0)
      :far -> 0
    end
  end
end
