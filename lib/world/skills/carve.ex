defmodule World.Skills.Carve do
  @moduledoc """
  The skill `carve` of a sculptor (plan 0004, D4): the head and the
  hands of a statue at near, carved in its stone from the full mesh of
  the person (the `carved` pieces of the node `figure`). A face cannot be
  cast in cells of 0.32 m; on a real statue a sculptor makes the head and
  the hands. At mid and far the cast has them. Its data: `meshes`.

  With `head` (plan 0005), the head goes where the measures put it: its
  top at `top`, the tip of its nose at `nose` [y, z], `narrow` the part
  of its width. With `hands`, each hand is `length` m from the wrist to
  the tip, turned `turn` degrees round the arm (180: the palm up), its
  wrist at `wrist` [x, z] (the hand on -x at [-x, z]).
  """
  @behaviour World.Skill
  alias World.{Mesh, Vec}
  alias World.Skills.Statue

  @names ~w(material head hands)

  @impl true
  def name, do: "carve"

  @impl true
  def trade, do: :sculptor

  @impl true
  def check(data, path), do: Statue.check(data, path, @names)

  # The head with its eyes and the two hands of the full mesh.
  @impl true
  def estimate(_data, :near), do: 12_000
  def estimate(_data, _level), do: 0

  @impl true
  def make(data, %{"figure" => %{"figure" => fig}}, _context) do
    o = Statue.o(data, @names)
    {look, matter} = Statue.material(o.material)

    meshes =
      for {name, {points, tris}} <- Map.get(fig, :carved, []),
          tris != [],
          do: Mesh.new(place(name, points, o), tris, look) |> Mesh.matter(matter)

    {nil, %{"meshes" => meshes}, %{}}
  end

  defp place("head", points, %{head: %{"top" => top, "nose" => [ny, nz], "narrow" => n}}) do
    {{_, _, _}, {_, _, z1}} = Vec.bounds(points)
    {_, y0, z0} = Enum.max_by(points, &elem(&1, 1))
    k = (top - nz) / (z1 - z0)
    for {x, y, z} <- points, do: {x * k * n, (y - y0) * k + ny, (z - z1) * k + top}
  end

  defp place("hand_" <> side, points, %{hands: %{"length" => l, "turn" => turn, "wrist" => [wx, wz]}}) do
    {{x0, y0, z0}, {x1, y1, z1}} = Vec.bounds(points)
    # hand_l is on -x (the left of the figure).
    {s, wrist} = if side == "l", do: {-1.0, x1}, else: {1.0, x0}
    k = l / (x1 - x0)
    {c, sn} = {:math.cos(turn * :math.pi() / 180), :math.sin(turn * :math.pi() / 180)}

    for {x, y, z} <- points do
      {dy, dz} = {(y - (y0 + y1) / 2) * k, (z - (z0 + z1) / 2) * k}
      {s * wx + (x - wrist) * k, dy * c - dz * sn, dy * sn + dz * c + wz}
    end
  end

  defp place(_name, points, _o), do: points
end
