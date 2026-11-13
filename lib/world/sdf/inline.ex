defmodule World.SDF.Inline do
  @moduledoc """
  The parts of the hot loop of the field (`World.SDF.fast/1`,
  `docs/plans/0010-sculpture-maps.md`, D13) as macros: each one is code
  in the clause that uses it, so the numbers of a clause stay floats in
  the registers of the JIT, with no box for each step. Each macro makes
  the same steps, in the same order, as the function of `World.SDF` that
  it stands for: the values are the same to the bit.
  """

  @doc """
  The value of the field after an edit with the distance `de`:
  `clamp(smin(d, de, k))` and the others. `hard` is more than 0 for a
  hard blend (a flat slope).
  """
  defmacro blend(:add, d, de, k, hard, limit) do
    quote do
      least = if unquote(d) < unquote(de), do: unquote(d), else: unquote(de)

      unquote(__MODULE__).clamp(
        unquote(__MODULE__).soft(least, unquote(d), unquote(de), unquote(k), unquote(hard)),
        unquote(limit)
      )
    end
  end

  # smax(d, -de, k) = -smin(-d, de, k).
  defmacro blend(:subtract, d, de, k, hard, limit) do
    quote do
      back = -unquote(d)
      least = if back < unquote(de), do: back, else: unquote(de)

      unquote(__MODULE__).clamp(
        -unquote(__MODULE__).soft(least, back, unquote(de), unquote(k), unquote(hard)),
        unquote(limit)
      )
    end
  end

  # smax(d, de, k) = -smin(-d, -de, k).
  defmacro blend(:crop, d, de, k, hard, limit) do
    quote do
      {back, out} = {-unquote(d), -unquote(de)}
      least = if back < out, do: back, else: out
      unquote(__MODULE__).clamp(-unquote(__MODULE__).soft(least, back, out, unquote(k), unquote(hard)), unquote(limit))
    end
  end

  @doc """
  The least of two values `a` and `b` (`least`), lower in their blend
  `k`: the smooth minimum, or the minimum with a flat slope for a hard
  blend.
  """
  defmacro soft(least, a, b, k, hard) do
    quote do
      if unquote(k) <= 0.0 do
        unquote(least)
      else
        gap = unquote(k) - abs(unquote(a) - unquote(b))
        gap = if gap > 0.0, do: gap, else: 0.0
        if unquote(hard) > 0.0, do: unquote(least) - gap / 2, else: unquote(least) - gap * gap / (4 * unquote(k))
      end
    end
  end

  @doc "The value in the limit of the field."
  defmacro clamp(v, limit) do
    quote do
      value = unquote(v)

      cond do
        value > unquote(limit) -> unquote(limit)
        value < -unquote(limit) -> -unquote(limit)
        true -> value
      end
    end
  end

  @doc "The value after a paint with the raise `h` and the blend `k`, at the distance `de` from its shape."
  defmacro lift(d, de, k, h, limit) do
    quote do
      more = -2 * unquote(de)

      w =
        if unquote(k) <= 0.0 do
          if more > 0.0, do: 1.0, else: 0.0
        else
          raw = 0.5 + 0.5 * more / unquote(k)

          cond do
            raw < 0.0 -> 0.0
            raw > 1.0 -> 1.0
            true -> raw
          end
        end

      unquote(__MODULE__).clamp(unquote(d) - unquote(h) * (w * w * (3.0 - 2.0 * w)), unquote(limit))
    end
  end

  @doc """
  The root of the nearest point of an ellipsoid (`World.SDF`, the
  ellipsoid): at most `steps` steps of Newton from `t`, each one in the
  code of the clause (no call, so no box for `t`).
  """
  defmacro root(t, _ux, _uy, _uz, _sx, _sy, _sz, 0), do: t

  defmacro root(t, ux, uy, uz, sx, sy, sz, steps) do
    quote do
      t0 = unquote(t)
      {qx, qy, qz} = {t0 + unquote(sx), t0 + unquote(sy), t0 + unquote(sz)}
      {a, b, c} = {unquote(ux) / qx, unquote(uy) / qy, unquote(uz) / qz}
      f = a * a + b * b + c * c - 1.0

      if f <= 1.0e-12 do
        t0
      else
        unquote(__MODULE__).root(
          t0 + f / (2.0 * (a * a / qx + b * b / qy + c * c / qz)),
          unquote(ux),
          unquote(uy),
          unquote(uz),
          unquote(sx),
          unquote(sy),
          unquote(sz),
          unquote(steps - 1)
        )
      end
    end
  end

  @doc "The larger of a value and 0."
  defmacro positive(v) do
    quote do
      value = unquote(v)
      if value > 0.0, do: value, else: 0.0
    end
  end
end
