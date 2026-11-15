defmodule World.Solids do
  @moduledoc """
  The simple solids of a model, as data
  (`docs/plans/0019-world-serves-the-projects.md`, 4.2): the output for
  a project that cannot draw a GLB, and draws boxes or SVG itself.

  - `of/2`: the shapes of a drawing from edits, with no build. Each edit
    with its copies is one solid: its shape and its size as in the data
    of an edit (`docs/format.md`, "A sculpture"), its place and its three
    axes in the axes of the model, its mode, its color and its role.
  - `boxes/1`: one box for each node and each material of a scene, for a
    model that is not from edits.

  The lengths are in meters. The axes are those of World: z is up, and
  the front of a model is to +y.
  """

  alias World.{Frame, GLB, Scene, SDF, Vec}
  alias World.Skills.Sculpt

  @doc """
  True when each node of the drawing is a sculpture: `of/2` gives its
  solids with no build.
  """
  def edits?(%{"nodes" => [_ | _] = nodes}), do: Enum.all?(nodes, &match?(%{"skill" => %{"sculpt" => _}}, &1))
  def edits?(_drawing), do: false

  @doc """
  The solids of a drawing from edits: `name`, `units`, `up`, `box` (the
  least and the most point of the shapes that add) and `parts`, each
  with its `name` and its `solids`. With the option `details: true`, the
  edits of the details of each part come too (the thin things: a rail,
  a mast), each with `"detail" => true`.
  """
  def of(%{"nodes" => nodes} = drawing, opts \\ []) do
    parts =
      for %{"name" => name, "skill" => %{"sculpt" => data}} <- nodes do
        groups = Map.get(data, "groups", %{})
        details = if opts[:details], do: Map.get(data, "details", []), else: []

        {name, Sculpt.edits(data["edits"], groups), Enum.flat_map(details, &Sculpt.edits(&1["edits"], groups))}
      end

    %{
      "name" => drawing["name"],
      "units" => "m",
      "up" => "z",
      "box" => box(SDF.bounds(Enum.flat_map(parts, &elem(&1, 1)))),
      "parts" =>
        for {name, edits, details} <- parts do
          %{
            "name" => name,
            "solids" => Enum.map(edits, &solid/1) ++ Enum.map(details, &Map.put(solid(&1), "detail", true))
          }
        end
    }
  end

  @doc """
  The boxes of a scene: for each node with a mesh, one box for each of
  its materials, with the sides along the axes of the model.
  """
  def boxes(%Scene{nodes: nodes} = scene) do
    frames = Scene.world_frames(scene)

    parts =
      for {%{primitives: [_ | _], extras: extras} = node, i} <- Enum.with_index(nodes),
          not is_map_key(extras, "collision") do
        solids =
          for p <- node.primitives, f <- node.instances || [%Frame{}] do
            frame = Frame.compose(frames[i], f)
            {lo, hi} = Vec.bounds(for pt <- Scene.positions(p), do: Frame.point(frame, pt))
            role = Atom.to_string(p.material)

            %{
              "shape" => "box",
              "size" => numbers(Vec.scale(Vec.sub(hi, lo), 0.5)),
              "at" => numbers(Vec.scale(Vec.add(lo, hi), 0.5)),
              "x" => [1.0, 0.0, 0.0],
              "y" => [0.0, 1.0, 0.0],
              "z" => [0.0, 0.0, 1.0],
              "mode" => "add",
              "role" => role,
              "color" => color(GLB.palette()[role])
            }
          end

        %{"name" => node.name, "solids" => solids}
      end

    {lo, hi} = Scene.bounds(scene)
    %{"name" => scene.name, "units" => "m", "up" => "z", "box" => [numbers(lo), numbers(hi)], "parts" => parts}
  end

  defp solid(%SDF.Edit{frame: f} = e) do
    %{
      "shape" => Atom.to_string(e.shape),
      "size" => size(e.shape, e.size),
      "at" => numbers(f.at),
      "x" => axis(f.x),
      "y" => axis(f.y),
      "z" => axis(f.z),
      "mode" => Atom.to_string(e.mode),
      "role" => e.material && Atom.to_string(e.material),
      "color" => e.color && hex(srgb(e.color))
    }
    |> put("blend", e.blend)
    |> put("raise", e.raise)
  end

  # (A key with the value 0 is not in the solid.)
  defp put(map, _key, v) when v == 0, do: map
  defp put(map, key, v), do: Map.put(map, key, r4(v))

  # The size of a shape, as in the data of an edit.
  defp size(:tube, {points, radii}), do: %{"points" => Enum.map(points, &numbers/1), "radii" => Enum.map(radii, &r4/1)}

  defp size(:extrude, {points, half, round}),
    do: %{"outline" => outline(points), "depth" => r4(2 * half)} |> put("round", round)

  defp size(:revolve, {points}), do: %{"profile" => outline(points)}
  defp size(_shape, size), do: numbers(size)

  defp outline(points), do: for({a, b} <- points, do: [r4(a), r4(b)])
  defp box(nil), do: nil
  defp box({lo, hi}), do: [numbers(lo), numbers(hi)]
  defp numbers(tuple), do: tuple |> Tuple.to_list() |> Enum.map(&r4/1)
  defp axis(tuple), do: tuple |> Tuple.to_list() |> Enum.map(&(Float.round(&1 / 1, 6) + 0.0))
  defp r4(v), do: Float.round(v / 1, 4) + 0.0

  defp color(%{"color" => [r, g, b]}), do: hex({r, g, b})
  defp color(_role), do: nil

  # The color of an edit is linear, each part from 0 to 1: back to sRGB, from 0 to 255.
  defp srgb({r, g, b}), do: {srgb(r), srgb(g), srgb(b)}
  defp srgb(c) when c <= 0.0031308, do: round(c * 12.92 * 255)
  defp srgb(c), do: round((1.055 * :math.pow(c, 1 / 2.4) - 0.055) * 255)

  defp hex({r, g, b}), do: "#" <> Base.encode16(<<r, g, b>>, case: :lower)
end
