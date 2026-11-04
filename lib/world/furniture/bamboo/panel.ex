defmodule World.Furniture.Bamboo.Panel do
  @moduledoc """
  The panels of the bamboo shop (`World.Furniture.Bamboo`), each on a
  rectangle of a frame: a corner `o`, the direction `u` along the pieces
  (length `lu`), the direction `v` across them (width `lv`), and the face
  `n` (the side of the lashing and of the person).

  - `slats/4`: slats split from a culm side by side: a seat;
  - `culms/4`: thin culms side by side: the uprights of a back, or the
    bars of a back across;
  - `lattice/4`: a frame inside the frame with four links to it (the
    backs of the bench and the armchairs of a set);
  - `lash/5`: a cord in a zigzag across the pieces, and a second cord in
    the other phase, so that the two make a row of X (the white cord over
    the seats and the backs in the photos).

  The sizes are by eye from the photos of the shops (`World.Furniture.Bamboo`).
  """
  alias World.{Detail, Vec}
  alias World.Furniture.Bamboo.Culm

  @gap 0.003

  @doc """
  Slats on the rectangle, each along `u` and `t` thick on `n`: options
  `width` (0.016), `t` (0.006), `gap` (3 mm), `lash` (the places of the
  rows of the lashing along `u`, as parts of `lu`: none). The meshes.
  """
  def slats({o, u, v, n}, lu, lv, opts) do
    w = Keyword.get(opts, :width, 0.016)
    t = Keyword.get(opts, :t, 0.006)
    centers = centers(lv, w, Keyword.get(opts, :gap, @gap))

    slats =
      for c <- centers do
        a = at(o, u, v, n, 0.0, c, 0.0)
        Culm.slat(a, Vec.add(a, Vec.scale(u, lu)), n, w, t)
      end

    slats ++ lash({o, u, v, n}, lu, centers, t, opts)
  end

  @doc """
  Thin culms on the rectangle, each along `u`, side by side across `v`,
  with their axes `d / 2` over the face: options `d` (0.016), `gap` (4
  mm), `ends` (`{:node, :node}`), `lash` (as `slats/4`). The meshes.
  """
  def culms({o, u, v, n}, lu, lv, opts) do
    d = Keyword.get(opts, :d, 0.016)
    centers = centers(lv, d, Keyword.get(opts, :gap, 0.004))

    culms =
      for c <- centers do
        a = at(o, u, v, n, 0.0, c, d / 2)
        b = at(o, u, v, n, lu, c, d / 2)
        Culm.piece(a, b, d: d, ends: Keyword.get(opts, :ends, {:node, :node}), node: 0.18, phase: 0.6)
      end

    culms ++ lash({o, u, v, n}, lu, centers, d, opts)
  end

  @doc """
  A lattice on the rectangle: a frame of thin culms inset by `inset`
  (option, 0.05 m), and a link from the middle of each of its sides to
  the frame around it. Option `d` (0.02). The meshes.
  """
  def lattice({o, u, v, n}, lu, lv, opts \\ []) do
    d = Keyword.get(opts, :d, 0.02)
    m = Keyword.get(opts, :inset, 0.05)
    p = fn su, sv -> at(o, u, v, n, su, sv, 0.0) end
    piece = fn a, b -> Culm.piece(a, b, d: d, ends: {:node, :node}, node: 0.3) end
    {u0, u1, v0, v1} = {m, lu - m, m, lv - m}
    {um, vm} = {lu / 2, lv / 2}

    [
      piece.(p.(u0, v0 - d / 2), p.(u0, v1 + d / 2)),
      piece.(p.(u1, v0 - d / 2), p.(u1, v1 + d / 2)),
      piece.(p.(u0 + d / 2, v0), p.(u1 - d / 2, v0)),
      piece.(p.(u0 + d / 2, v1), p.(u1 - d / 2, v1)),
      piece.(p.(0.0, vm), p.(u0 - d / 2, vm)),
      piece.(p.(u1 + d / 2, vm), p.(lu, vm)),
      piece.(p.(um, 0.0), p.(um, v0 - d / 2)),
      piece.(p.(um, v1 + d / 2), p.(um, lv))
    ]
  end

  @doc """
  The rows of a lashing across pieces at `centers` (their places across
  `v`), `h` over the face: a row at each place of `lash` (parts of `lu`),
  two cords in a zigzag of 8 mm, each in the other phase. No cord at far.
  """
  def lash({o, u, v, n}, lu, centers, h, opts) do
    if Detail.level() == :far do
      []
    else
      for f <- Keyword.get(opts, :lash, []), phase <- [1, -1] do
        centers
        |> Enum.with_index()
        |> Enum.map(fn {c, i} ->
          s = if rem(i, 2) == 0, do: phase, else: -phase
          at(o, u, v, n, f * lu + s * 0.008, c, h + 0.0012)
        end)
        |> Culm.cord()
      end
    end
  end

  # The centers of pieces of width `w` with a gap, across a width `lv`,
  # with the rest at the two sides.
  defp centers(lv, w, gap) do
    count = max(floor((lv + gap) / (w + gap)), 1)
    rest = lv - (count * w + (count - 1) * gap)
    for i <- 0..(count - 1), do: rest / 2 + w / 2 + i * (w + gap)
  end

  defp at(o, u, v, n, su, sv, sn),
    do: o |> Vec.add(Vec.scale(u, su)) |> Vec.add(Vec.scale(v, sv)) |> Vec.add(Vec.scale(n, sn))
end
