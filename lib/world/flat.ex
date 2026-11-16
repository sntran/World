defmodule World.Flat do
  @moduledoc """
  The flat look of a model, for a project that draws many small things
  with no image (`docs/plans/0019-world-serves-the-projects.md`, 4.2): a
  scene becomes one node with one mesh. Each face has its own three
  points, the normal of the face and one color at each point, so the
  model needs no image and no material of its own, and a client draws
  its copies in one batch.

  The color of a face is the color of its points when the mesh has
  colors (a model from edits with the look `flat`), else the color of
  its material: the color of the scene for the role, or the color of the
  palette. The points are at their places in the axes of the model (the
  frames of the nodes, the copies of a node, the bones of a skin at the
  pose of the scene). With a `budget`, the mesh has at most that count
  of faces (`World.Simplify`), and each face has the color of the nearest
  face of the mesh before.

  With `roles: true` the scene is the light look: one node with one
  primitive for each material of the model (its role), flat faces, no
  color at the points and no image. The materials of the scene stay, so
  a project gives each role its own material. A budget keeps the border
  of two roles: each face keeps its role.
  """

  alias World.{Cast, Frame, GLB, Scene, Simplify, Vec}

  @gray {200, 200, 200}

  @doc """
  The flat scene of a scene. The option `budget` is the most faces; with
  `roles: true`, the light look (a primitive for each material).
  """
  def scene(%Scene{nodes: nodes, skins: skins} = scene, opts \\ []) do
    frames = Scene.world_frames(scene)
    roles? = Keyword.get(opts, :roles, false)

    # Each face: its three points, its color, and its role (one role for all in the flat look).
    faces =
      for {%{primitives: [_ | _], extras: extras} = node, i} <- Enum.with_index(nodes),
          not is_map_key(extras, "collision"),
          p <- node.primitives,
          points <- places(node, p, frames, i, skins),
          {corners, color} <- faces(p, List.to_tuple(points), color(scene, p)),
          do: {corners, color, if(roles?, do: p.material, else: :paint)}

    faces = if opts[:wrap], do: wrap(faces), else: faces
    faces = if opts[:budget] && length(faces) > opts[:budget], do: fewer(faces, opts[:budget]), else: faces

    primitives =
      for {role, faces} <- Enum.sort(Enum.group_by(faces, &elem(&1, 2))) do
        %Scene.Primitive{
          material: role,
          positions: for({{a, b, c}, _, _} <- faces, p <- [a, b, c], do: p),
          normals: for({{a, b, c}, _, _} <- faces, n = normal(a, b, c), _ <- 1..3, do: n),
          indices: Enum.to_list(0..(3 * length(faces) - 1)//1),
          colors: if(roles?, do: nil, else: for({_, color, _} <- faces, _ <- 1..3, do: color))
        }
      end

    materials =
      if roles?,
        do:
          for(
            %{material: role} = p <- primitives,
            spec = scene.materials[role],
            spec != nil,
            into: %{},
            do: {role, plain(spec, color(scene, p))}
          ),
        # (The color of each point is the color of the model: the material is white.)
        else: %{paint: %{"color" => [255, 255, 255], "roughness" => 0.9, "metalness" => 0.0}}

    %Scene{
      name: scene.name,
      extras: Map.take(scene.extras, ["size", "sources"]),
      nodes: [%Scene.Node{name: scene.name, primitives: primitives}],
      materials: materials
    }
  end

  # A material with no image: the light look has no UVs. (A role with no
  # material in the scene has the material of the palette, as in each GLB.)
  defp plain(spec, {r, g, b}),
    do: spec |> Map.take(~w(roughness metalness double_sided)) |> Map.put("color", [r, g, b])

  @doc "The count of the faces of a flat scene."
  def faces(%Scene{nodes: [%{primitives: primitives}]}),
    do: primitives |> Enum.map(&div(length(&1.indices), 3)) |> Enum.sum()

  # The points of a primitive in the axes of the model: one list for each copy of its node. The points of
  # a skin are at the places that its bones give.
  defp places(%{skin: nil} = node, p, frames, i, _skins) do
    for f <- node.instances || [%Frame{}] do
      frame = Frame.compose(frames[i], f)
      for pt <- Scene.positions(p), do: Frame.point(frame, pt)
    end
  end

  defp places(node, p, frames, _i, skins) do
    skin = Enum.at(skins, node.skin)

    bones =
      skin.joints
      |> Enum.zip(skin.inverse_bind)
      |> Enum.map(fn {j, ib} -> Frame.compose(frames[j], ib) end)
      |> List.to_tuple()

    [
      for {pt, js, ws} <- Enum.zip([p.positions, p.joints, p.weights]) do
        Enum.zip(Tuple.to_list(js), Tuple.to_list(ws))
        |> Enum.map(fn {j, w} -> Vec.scale(Frame.point(elem(bones, j), pt), w) end)
        |> Enum.reduce(&Vec.add/2)
      end
    ]
  end

  # The faces of a primitive: `{{a, b, c}, color}`, with the color of the first point of the face, or `color`.
  defp faces(p, at, color) do
    colors = p.colors && List.to_tuple(p.colors)

    for [a, b, c] <- Enum.chunk_every(p.indices, 3) do
      {{elem(at, a), elem(at, b), elem(at, c)}, if(colors, do: rgb(elem(colors, a)), else: color)}
    end
  end

  defp rgb({r, g, b, _alpha}), do: {r, g, b}
  defp rgb(color), do: color

  # The color of the material of a primitive: of the scene, else of the palette, else gray.
  defp color(scene, %{material: role}) do
    case {scene.materials[role], GLB.palette()[Atom.to_string(role)]} do
      {%{"color" => [r, g, b]}, _} -> {r, g, b}
      {_, %{"color" => [r, g, b]}} -> {r, g, b}
      _ -> @gray
    end
  end

  # At most `budget` faces: the points that are at one place become one point, the collapse makes fewer
  # faces, and each face that is left has the color of the nearest face of the first mesh.
  defp fewer(faces, budget) do
    key = fn {x, y, z} -> {round(x * 10_000), round(y * 10_000), round(z * 10_000)} end

    {index, points} =
      Enum.reduce(faces, {%{}, []}, fn {{a, b, c}, _, _}, acc ->
        Enum.reduce([a, b, c], acc, fn p, {index, points} ->
          if is_map_key(index, key.(p)),
            do: {index, points},
            else: {Map.put(index, key.(p), map_size(index)), [p | points]}
        end)
      end)

    welded =
      for {{a, b, c}, _, role} <- faces,
          ids = [index[key.(a)], index[key.(b)], index[key.(c)]],
          length(Enum.uniq(ids)) == 3,
          do: {ids, role}

    {points, small} = Simplify.collapse(Enum.reverse(points), welded, budget)
    at = List.to_tuple(points)
    nearest = nearest(faces)

    for {[a, b, c], role} <- small do
      corners = {elem(at, a), elem(at, b), elem(at, c)}
      {color, _} = nearest.(corners)
      {corners, color, role}
    end
  end

  # The color and the role of the face of `faces` nearest to a face (by the middles of the faces, in a
  # grid of cells).
  defp nearest(faces) do
    middles = for {{a, b, c}, color, role} <- faces, do: {middle(a, b, c), {color, role}}
    {lo, hi} = Vec.bounds(Enum.map(middles, &elem(&1, 0)))
    cell = max(Enum.max(Tuple.to_list(Vec.sub(hi, lo))) / 24, 1.0e-6)
    place = fn {x, y, z} -> {floor(x / cell), floor(y / cell), floor(z / cell)} end
    grid = Enum.group_by(middles, &place.(elem(&1, 0)))

    fn {a, b, c} ->
      m = middle(a, b, c)
      {i, j, k} = place.(m)
      near = for di <- -1..1, dj <- -1..1, dk <- -1..1, item <- Map.get(grid, {i + di, j + dj, k + dk}, []), do: item
      {_, found} = Enum.min_by(if(near == [], do: middles, else: near), fn {p, _} -> Vec.len(Vec.sub(p, m)) end)
      found
    end
  end

  # One closed skin round the whole model, for a model of many thin parts that a collapse cannot make
  # small: the cast of the faces in a grid (`World.Cast`; the longest side of the model is 48 cells), with
  # two steps of smoothing. Each face of the skin has the color and the role of the nearest face of the model.
  defp wrap(faces) do
    points = for {{a, b, c}, _, _} <- faces, p <- [a, b, c], do: p
    {lo, hi} = Vec.bounds(points)
    step = Enum.max(Tuple.to_list(Vec.sub(hi, lo))) / 48
    tris = for i <- 0..(length(faces) - 1)//1, do: [3 * i, 3 * i + 1, 3 * i + 2]
    %{dims: {nx, _, _}} = grid = Cast.surface(Cast.solid([{points, tris}], step))
    skin = Cast.join(grid, [Cast.quads(grid, {0, nx - 2})], :paint, relax: 2)
    at = List.to_tuple(skin.points)
    nearest = nearest(faces)

    for [a, b, c] <- skin.faces do
      corners = {elem(at, a), elem(at, b), elem(at, c)}
      {color, role} = nearest.(corners)
      {corners, color, role}
    end
  end

  defp middle(a, b, c), do: Vec.scale(Vec.add(Vec.add(a, b), c), 1 / 3)

  defp normal(a, b, c) do
    n = Vec.cross(Vec.sub(b, a), Vec.sub(c, a))
    if Vec.len(n) > 0, do: Vec.norm(n), else: {0.0, 0.0, 1.0}
  end
end
