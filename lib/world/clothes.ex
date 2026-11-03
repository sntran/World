defmodule World.Clothes do
  @moduledoc """
  The clothes that World makes for a person (`World.People`): the packs
  of MakeHuman have no jacket for a trip in the rain or the cold. Each
  item is an item of the clothes as the items of MakeHuman (a mesh, its
  fit to the body, a texture), made from the surface of the base mesh.
  Now the items are three presets of jackets:

  - `world_rain_shell`: a thin shell to the hips, with a high collar and
    the hood folded at the back of the neck;
  - `world_softshell`: a jacket close to the body, to the hips, with a
    collar;
  - `world_down_jacket`: a thick jacket in baffles, to the hips, with a
    collar.

  A jacket has the faces of the body under the torso, the arms to the
  wrists and the neck (by the bones of the weights of each point), each
  point moved out along the normal of the body. Its fit refers to the
  point of the body under each of its points, so it changes with the
  shape of the body, and it hides the points of the body inside it. Its
  texture is light, so the color of an order tints it.

  `files/0` gives the files; `mix run scripts/clothes.exs` writes them in
  `priv/makehuman/clothes/`. `World.People.Data.assets/0` adds their
  entries (`entries/0`) to the clothes of `assets.json`. The license is
  that of World (AGPL-3.0).
  """
  alias World.People.Data
  alias World.Vec

  # name, the thickness (dm), the extra thickness of the baffles of a
  # down jacket, the extra thickness at the back of the neck (a folded
  # hood), and the part of the neck under the collar.
  @jackets [
    {"world_rain_shell", %{thick: 0.19, puff: 0.0, hood: 0.28, collar: 1.0, grain: 4}},
    {"world_softshell", %{thick: 0.17, puff: 0.0, hood: 0.0, collar: 0.6, grain: 10}},
    {"world_down_jacket", %{thick: 0.3, puff: 0.12, hood: 0.0, collar: 0.7, grain: 6}}
  ]

  # The bones of the points under a jacket.
  @upper ~w(spine_01 spine_02 spine_03 clavicle_l clavicle_r upperarm_l upperarm_r lowerarm_l lowerarm_r)
  @hips ~w(pelvis thigh_l thigh_r)

  # The distance between two baffles of a down jacket (dm).
  @baffle 0.9

  # The more room at the hem (dm), less to 0 at 1 dm over it.
  @hem_room 0.12

  @doc """
  The names of the items.

      iex> World.Clothes.names()
      ["world_rain_shell", "world_softshell", "world_down_jacket"]
  """
  def names, do: Enum.map(@jackets, &elem(&1, 0))

  @doc "The files of the items: a list of `{file name, binary}` in `priv/makehuman/clothes/`."
  def files do
    Enum.flat_map(@jackets, fn {name, spec} ->
      {obj, fit} = make(name, spec)
      [{name <> ".obj.gz", gzip(obj)}, {name <> ".mhclo.gz", gzip(fit)}, {name <> ".png", texture(spec)}]
    end)
  end

  @doc "The entries of the items in `assets.json` (as the entries of `scripts/makehuman.py`)."
  def entries do
    Map.new(@jackets, fn {name, spec} ->
      {name,
       %{
         "pack" => "world",
         "license" => "AGPL-3.0",
         "obj" => name <> ".obj.gz",
         "fit" => name <> ".mhclo.gz",
         "texture" => name <> ".png",
         "color" => List.duplicate(shade(spec), 3),
         "transparent" => false
       }}
    end)
  end

  # The mesh (an OBJ file) and the fit (an MHCLO file) of a jacket.
  defp make(name, spec) do
    %{points: points, uvs: uvs, groups: groups} = Data.base()
    faces = Map.fetch!(groups, "body")

    joint = fn g ->
      groups |> Map.fetch!(g) |> Enum.flat_map(fn f -> Enum.map(f, &elem(points, elem(&1, 0))) end) |> Vec.mean()
    end

    {_, hip, _} = joint.("joint-l-upper-leg")
    {_, neck, _} = joint.("joint-neck")
    {_, head, _} = joint.("joint-head")
    hem = hip - 0.5
    collar = neck + spec.collar * (head - neck)

    bone = dominant()

    inside? = fn v ->
      {_, y, _} = elem(points, v)
      b = Map.get(bone, v)
      (b in @upper and y >= hem) or (b in @hips and y >= hem) or (b == "neck_01" and y <= collar)
    end

    jacket = Enum.filter(faces, fn f -> Enum.all?(f, &inside?.(elem(&1, 0))) end)
    normals = normals(points, faces)
    {_, _, nape} = joint.("joint-neck")

    vs = jacket |> Enum.flat_map(fn f -> Enum.map(f, &elem(&1, 0)) end) |> Enum.uniq() |> Enum.sort()
    index = vs |> Enum.with_index(1) |> Map.new()
    ts = jacket |> Enum.flat_map(fn f -> Enum.map(f, &elem(&1, 1)) end) |> Enum.uniq() |> Enum.sort()
    tindex = ts |> Enum.with_index(1) |> Map.new()

    move = fn v ->
      {_, y, z} = p = elem(points, v)
      n = Map.fetch!(normals, v)
      puff = spec.puff * (0.5 + 0.5 * :math.cos(2 * :math.pi() * y / @baffle))
      # The folded hood: the back of the neck and the top of the back.
      hood =
        if spec.hood > 0 and y > neck - 0.4 and z < nape, do: spec.hood * min(1.0, (y - neck + 0.4) / 0.6), else: 0.0

      # The hem is looser: the waist of the pants stays inside.
      hem_room = @hem_room * min(1.0, max(0.0, (hem + 1.0 - y) / 1.0))
      {p, Vec.scale(n, spec.thick + puff + hood + hem_room)}
    end

    moved = Map.new(vs, &{&1, move.(&1)})

    obj =
      IO.iodata_to_binary([
        "# The jacket #{name} of World (World.Clothes).\n",
        for v <- vs do
          {p, d} = Map.fetch!(moved, v)
          {x, y, z} = Vec.add(p, d)
          ["v ", num(x), " ", num(y), " ", num(z), "\n"]
        end,
        for t <- ts do
          {u, w} = elem(uvs, t)
          ["vt ", num(u), " ", num(w), "\n"]
        end,
        "g #{name}\n",
        for f <- jacket do
          ["f", for({v, t} <- f, do: [" ", Integer.to_string(index[v]), "/", Integer.to_string(tindex[t])]), "\n"]
        end
      ])

    # The points of the body inside the jacket: each point under it with
    # all its neighbors under it (a point at an edge stays, so the body
    # has no hole at the hem, the cuffs and the collar).
    under = MapSet.new(vs)
    ring = neighbors(faces)
    hidden = Enum.filter(vs, fn v -> Enum.all?(Map.get(ring, v, []), &MapSet.member?(under, &1)) end)

    fit =
      IO.iodata_to_binary([
        "# The fit of the jacket #{name} of World to the base mesh hm08.\n",
        "name #{name}\nobj_file #{name}.obj\n",
        # The scales of male_casualsuit01 of MakeHuman: two points of the
        # body and their distance in the base mesh, for each axis.
        "x_scale 5399 11998 1.4340\nz_scale 962 5320 2.0001\ny_scale 791 881 2.4098\n",
        "verts 0\n",
        for v <- vs do
          {_, {dx, dy, dz}} = Map.fetch!(moved, v)
          s = Integer.to_string(v)
          [s, " ", s, " ", s, " 1.0 0.0 0.0 ", num(dx), " ", num(dy), " ", num(dz), "\n"]
        end,
        "delete_verts\n",
        Enum.map(hidden, &[Integer.to_string(&1), "\n"])
      ])

    {obj, fit}
  end

  # The bone with the largest weight of each point of the body.
  defp dominant do
    for {bone, pairs} <- Data.weights(), [p, w] <- pairs, reduce: %{} do
      acc -> Map.update(acc, p, {bone, w}, fn {_, w0} = old -> if w > w0, do: {bone, w}, else: old end)
    end
    |> Map.new(fn {p, {bone, _}} -> {p, bone} end)
  end

  # The normal of each point of the faces: the sum of the normals of its
  # faces (each face of the body is a quad: the cross of its diagonals),
  # made a unit.
  defp normals(points, faces) do
    faces
    |> Enum.reduce(%{}, fn f, acc ->
      [a, b, c, d] = Enum.map(f, &elem(points, elem(&1, 0)))
      n = Vec.cross(Vec.sub(c, a), Vec.sub(d, b))
      Enum.reduce(f, acc, fn {v, _}, acc -> Map.update(acc, v, n, &Vec.add(&1, n)) end)
    end)
    |> Map.new(fn {v, n} -> {v, Vec.norm(n)} end)
  end

  # The neighbors of each point: the other points of its faces.
  defp neighbors(faces) do
    Enum.reduce(faces, %{}, fn f, acc ->
      vs = Enum.map(f, &elem(&1, 0))
      Enum.reduce(vs, acc, fn v, acc -> Map.update(acc, v, vs -- [v], &Enum.uniq(&1 ++ (vs -- [v]))) end)
    end)
  end

  # A number with 5 decimals, so the files are the same at each run.
  defp num(x), do: :erlang.float_to_binary(x / 1, decimals: 5)

  defp gzip(data), do: :zlib.gzip(data)

  # The gray of the texture of a jacket.
  defp shade(_spec), do: 225

  # A light texture of 128 x 128 texels: the gray of `shade/1`, with a
  # small grain of the fabric (a grid of `grain` texels), the same bytes
  # at each run.
  defp texture(spec) do
    g = shade(spec)

    rows =
      for y <- 0..127 do
        for x <- 0..127, into: <<>> do
          d = if rem(x, spec.grain) == 0 or rem(y, spec.grain) == 0, do: -8, else: 0
          n = :erlang.phash2({x, y}, 7) - 3
          c = g + d + n
          <<c, c, c>>
        end
      end

    World.PNG.encode(rows, 3)
  end
end
