defmodule World.Kit do
  @moduledoc """
  Small helpers for the models of items (appliances, power stations,
  electrical parts): sizes in inches, boxes with round edges, a cavity
  with an open front, handles, feet, grilles, and the ports of a joint
  that stay where the shapes are.

  The axes are those of World: x to the right side, y to the front (the
  side that a person uses), z up. A model stands on z = 0, centered on x
  and y.
  """
  alias World.{Frame, Part, Shape, Vec}
  @doc "Inches to meters."
  def inch(x), do: x * 0.0254

  @doc "Millimeters to meters."
  def mm(x), do: x / 1000

  @doc """
  The same port on two parts: a child with this port stays where its
  shapes are, and its joint turns (or slides) around the axis.
  """
  def same(name, at, axis, up), do: Part.port(name, at, axis, up)

  @doc "A box with round edges: `r` is the part of each side that is round (0 to 0.5)."
  def rbox(a, b, material, r \\ 0.08), do: Shape.box(a, b, material, round: r, smooth: 2)

  @doc """
  The walls of a box with an open side (a cavity): the open side is
  `:front` (y), `:top` (z) or `:bottom`. `t` is the thickness of the walls.
  """
  def cavity({x0, y0, z0}, {x1, y1, z1}, t, material, open \\ :front) do
    walls = [
      {{x0, y0, z0}, {x0 + t, y1, z1}},
      {{x1 - t, y0, z0}, {x1, y1, z1}},
      {{x0 + t, y0, z0}, {x1 - t, y0 + t, z1}}
    ]

    walls =
      case open do
        :front -> walls ++ [{{x0 + t, y0 + t, z0}, {x1 - t, y1, z0 + t}}, {{x0 + t, y0 + t, z1 - t}, {x1 - t, y1, z1}}]
        :top -> walls ++ [{{x0 + t, y0 + t, z0}, {x1 - t, y1 - t, z0 + t}}, {{x0 + t, y1 - t, z0}, {x1 - t, y1, z1}}]
      end

    for {a, b} <- walls, do: Shape.box(a, b, material)
  end

  @doc """
  A panel in the plane y0..y1 with a square hole of half side `half`
  around `{cx, cz}`: four boxes.
  """
  def holed_panel({x0, x1}, {z0, z1}, {y0, y1}, {cx, cz}, half, material) do
    [
      Shape.box({x0, y0, z0}, {x1, y1, cz - half}, material),
      Shape.box({x0, y0, cz + half}, {x1, y1, z1}, material),
      Shape.box({x0, y0, cz - half}, {cx - half, y1, cz + half}, material),
      Shape.box({cx + half, y0, cz - half}, {x1, y1, cz + half}, material)
    ]
  end

  @doc """
  A flat slab from z0 to z1 with a hole from `{hx0, hy0}` to `{hx1, hy1}`
  (a counter with the hole of a sink): four boxes.
  """
  def holed_slab({x0, y0, z0}, {x1, y1, z1}, {hx0, hy0}, {hx1, hy1}, material) do
    [
      Shape.box({x0, y0, z0}, {hx0, y1, z1}, material),
      Shape.box({hx1, y0, z0}, {x1, y1, z1}, material),
      Shape.box({hx0, y0, z0}, {hx1, hy0, z1}, material),
      Shape.box({hx0, hy1, z0}, {hx1, y1, z1}, material)
    ]
  end

  @doc """
  A handle: a bar of radius `r` from `a` to `b`, out of the surface by
  `out` along the direction `dir` (two posts and the grip).
  """
  def handle({ax, ay, az} = a, {bx, by, bz} = b, {dx, dy, dz}, out, r, material) do
    o = fn {x, y, z} -> {x + dx * out, y + dy * out, z + dz * out} end
    Shape.sweep([a, o.({ax, ay, az}), o.({bx, by, bz}), b], r, material, sides: 10)
  end

  @doc "Feet: a short cylinder of radius `r` and height `h` under each point `{x, y}`."
  def feet(points, r, h, material \\ :rubber) do
    for {x, y} <- points, do: Shape.cylinder(r, h, material, sides: 12, frame: Frame.move({x, y, 0.0}))
  end

  @doc "A cylinder from the point `a` along the direction `axis` (a unit vector), of length `len`."
  def rod(a, axis, r, len, material, sides \\ 12) do
    Shape.cylinder(r, len, material, sides: sides, frame: Frame.new(a, axis, Vec.perpendicular(axis)))
  end

  @doc """
  A grille of `n` bars on a face: from `a` to `b` (the first bar), each
  next bar moved by `step`.
  """
  def bars(a, b, step, n, r, material) do
    for k <- 0..(n - 1) do
      move = fn {x, y, z} -> {x + elem(step, 0) * k, y + elem(step, 1) * k, z + elem(step, 2) * k} end
      Shape.sweep([move.(a), move.(b)], r, material, sides: 6)
    end
  end

  @doc "A knob on a face that looks to `axis`, at `at`: radius `r`, length `len`, with a mark."
  def knob(name, at, axis, up, r, len, material \\ :chrome) do
    body =
      Shape.lathe([{0.0, 0.0}, {r, 0.0}, {r, len * 0.8}, {r * 0.85, len}, {0.0, len}], material,
        sides: 16,
        frame: Frame.new(at, axis, up)
      )

    Part.new(name, :knob, body, [same(name, at, axis, up)], detail: :near)
  end
end
