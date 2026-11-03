defmodule World.Sewing do
  @moduledoc """
  The sewing shop of the world: it makes the clothes of a person
  (`World.People`) as a tailor makes them.

  A garment is a set of pieces of one fabric. A tailor cuts each piece
  from a pattern: an outline on the body, with the ease of the fit (the
  room between the body and the cloth). The pieces join at their seams:
  the faces between two pieces on the same surface (a face with points
  of the two pieces). A point in two pieces has the mean ease of the two. A piece is on the
  surface of the body (`"body"`) or on the skirt of the base mesh
  (`"helper-skirt"`, a tube from the waist to the ankles: the panels of
  an áo dài hang from it, not on the legs).

  Each garment has its layer: 0 next to the skin (a bra), 1 pants, 2 a
  top over the pants (a T-shirt, an áo dài over its quần), 3 a jacket. The cloth of a layer is out of the body by the base
  of its layer, its ease and the thickness of its fabric, so an inner
  layer is always nearer to the body than the layers over it. Two pieces
  of two layers that meet overlap (the hem of the bodice of an áo dài is
  under the top of its pants), so no skin shows between them.

  A fabric has its thickness, its span (how much it bridges the dips of
  the body: a knit follows the body, a woven silk spans from the bust
  down), the grain of its weave and its shade. The span runs when the
  garment fits a body (`World.People.Human`), on that body: a garment is
  the same on a small and a large bust.

  A garment can give a shape to the body under it: the cups of a bra
  lift the bust, make it round, and take the points away (targets of
  MakeHuman). The body and all its clothes take that shape when the bra
  is worn.

  `garments/0` gives the garments, `files/0` their files (a mesh, a fit
  to the base mesh, a texture: as the clothes of MakeHuman), `entries/0`
  their entries in `assets.json` (`World.People.Data.assets/0`). `mix run
  scripts/clothes.exs` writes the files in `priv/makehuman/clothes/`.
  The license is that of World (AGPL-3.0).
  """
  alias World.People.Data
  alias World.Vec

  # The base of each layer (dm out of the body).
  @layers %{0 => 0.004, 1 => 0.03, 2 => 0.07, 3 => 0.15}

  # The fabrics: the thickness (dm), the span (steps of the drape), the
  # grain of the weave (a grid of texels) and the shade (gray, 0..255).
  @fabrics %{
    "silk" => %{thick: 0.006, span: 24, grain: 16, shade: 236},
    "satin" => %{thick: 0.006, span: 0, grain: 16, shade: 238},
    "cotton_jersey" => %{thick: 0.012, span: 8, grain: 4, shade: 228},
    "cotton_twill" => %{thick: 0.016, span: 0, grain: 3, shade: 222},
    "foam_cup" => %{thick: 0.025, span: 0, grain: 8, shade: 240},
    "nylon_shell" => %{thick: 0.02, span: 16, grain: 4, shade: 225},
    "softshell" => %{thick: 0.02, span: 12, grain: 10, shade: 225},
    "down" => %{thick: 0.1, span: 8, grain: 6, shade: 225}
  }

  # The bones of the parts of the body (the bone with the largest weight
  # of a point).
  @torso ~w(spine_01 spine_02 spine_03 clavicle_l clavicle_r)
  @arms ~w(upperarm_l upperarm_r lowerarm_l lowerarm_r)
  @legs ~w(thigh_l thigh_r calf_l calf_r)

  # The bra: the targets of MakeHuman of its shape (from the tests of the
  # áo dài: round, higher, no point).
  @bra_shape [
    {"breast/breast-point-decr", 1.0},
    {"breast/breast-trans-up", 1.0},
    {"breast/breast-volume-vert-up", 0.5}
  ]

  # The garments. A level of a cut is a landmark (`landmarks/0`) and an
  # offset (dm), or a point between two landmarks.
  @garments [
    %{
      name: "world_bra",
      layer: 0,
      fabric: "foam_cup",
      shape: @bra_shape,
      pieces: [
        # The two cups: the area of the breasts, at the front.
        %{
          name: "cups",
          on: "body",
          bones: @torso,
          region: "cups",
          front: true,
          y: {{:underbust, -0.05}, {:nipple, 0.75}}
        },
        # The band under the bust, around the torso.
        %{name: "band", on: "body", bones: @torso, y: {{:underbust, -0.4}, {:underbust, 0.05}}},
        # The straps: from the cups over the shoulders to the band at the back.
        %{name: "straps", on: "body", bones: @torso, x: {0.65, 0.95}, y: {{:underbust, -0.4}, {:neck, -0.1}}}
      ]
    },
    %{
      name: "world_ao_dai",
      layer: 2,
      fabric: "silk",
      pieces: [
        # The bodice to the waist, with the long sleeves to the wrists,
        # and the stand collar.
        %{
          name: "bodice",
          on: "body",
          bones: @torso ++ ["pelvis"],
          y: {{:waist, -0.7}, {:neck, -0.05}},
          ease: 0.01,
          drape: true
        },
        %{name: "sleeves", on: "body", bones: @arms, ease: 0.02},
        %{name: "collar", on: "body", bones: ["neck_01"], y: {{:neck, -0.6}, {:neck, :head, 0.55}}},
        # The two long panels, to the middle of the calf, with the slits
        # at the sides from the waist down.
        %{name: "front_panel", on: "helper-skirt", y: {{:knee, :ankle, 0.55}, {:waist, 0.0}}, angle: {:front, 70}},
        %{name: "back_panel", on: "helper-skirt", y: {{:knee, :ankle, 0.55}, {:waist, 0.0}}, angle: {:back, 70}}
      ]
    },
    %{
      name: "world_quan",
      layer: 1,
      fabric: "satin",
      pieces: [
        # The wide pants of an áo dài: from the waist to the ankles,
        # 0.5 cm of ease at the hips, 3.5 cm at the ankles.
        %{
          name: "legs",
          on: "body",
          bones: ["spine_01", "pelvis"] ++ @legs,
          y: {{:ankle, 0.25}, {:waist, 0.2}},
          ease: {:flare, 0.02, 0.32}
        }
      ]
    },
    %{
      name: "world_t_shirt",
      layer: 2,
      fabric: "cotton_jersey",
      pieces: [
        # The front and the back to the hips, with a crew neck.
        %{
          name: "body",
          on: "body",
          bones: @torso ++ ["pelvis", "thigh_l", "thigh_r"],
          y: {{:hip, -0.6}, {:neck, -0.35}},
          ease: 0.02,
          room: 0.08,
          drape: true
        },
        # The short sleeves: a fourth of the arm.
        %{name: "sleeves", on: "body", bones: @arms, arm: 0.27, ease: 0.05}
      ]
    },
    %{
      name: "world_pants",
      layer: 1,
      fabric: "cotton_twill",
      pieces: [
        # Straight pants from the waist to the ankles.
        %{
          name: "legs",
          on: "body",
          bones: ["spine_01", "pelvis"] ++ @legs,
          y: {{:ankle, 0.3}, {:waist, -0.2}},
          ease: {:flare, 0.02, 0.2}
        }
      ]
    },
    %{
      name: "world_rain_shell",
      layer: 3,
      fabric: "nylon_shell",
      pieces: [
        # A thin shell to the hips, with a high collar and the hood folded
        # at the back of the neck.
        %{
          name: "shell",
          on: "body",
          bones: @torso ++ @arms ++ ["pelvis", "thigh_l", "thigh_r"],
          y: {{:hip, -0.5}, nil},
          ease: 0.02,
          room: 0.12,
          hood: 0.28,
          drape: true
        },
        %{name: "collar", on: "body", bones: ["neck_01"], y: {nil, {:neck, :head, 1.0}}, ease: 0.02, hood: 0.28}
      ]
    },
    %{
      name: "world_softshell",
      layer: 3,
      fabric: "softshell",
      pieces: [
        # A jacket close to the body, to the hips, with a collar.
        %{
          name: "shell",
          on: "body",
          bones: @torso ++ @arms ++ ["pelvis", "thigh_l", "thigh_r"],
          y: {{:hip, -0.5}, nil},
          room: 0.12,
          drape: true
        },
        %{name: "collar", on: "body", bones: ["neck_01"], y: {nil, {:neck, :head, 0.6}}}
      ]
    },
    %{
      name: "world_down_jacket",
      layer: 3,
      fabric: "down",
      pieces: [
        # A thick jacket in baffles, to the hips, with a collar.
        %{
          name: "shell",
          on: "body",
          bones: @torso ++ @arms ++ ["pelvis", "thigh_l", "thigh_r"],
          y: {{:hip, -0.5}, nil},
          ease: 0.05,
          room: 0.12,
          puff: 0.12,
          drape: true
        },
        %{name: "collar", on: "body", bones: ["neck_01"], y: {nil, {:neck, :head, 0.7}}, ease: 0.05, puff: 0.12}
      ]
    }
  ]

  # The points of the body in the base mesh are the first ones (the
  # helpers come after them).
  @body 13380

  # The distance between two baffles of a down jacket (dm).
  @baffle 0.9

  @doc """
  The names of the garments.

      iex> World.Sewing.names()
      ["world_bra", "world_ao_dai", "world_quan", "world_t_shirt", "world_pants", "world_rain_shell", "world_softshell", "world_down_jacket"]
  """
  def names, do: Enum.map(@garments, & &1.name)

  @doc """
  The garments: each with its name, layer, fabric, pieces, and the shape
  that it gives to the body (a list of `{target, weight}`).
  """
  def garments, do: Enum.map(@garments, &Map.put_new(&1, :shape, []))

  @doc """
  The fabrics, by name.

      iex> World.Sewing.fabrics()["silk"].thick
      0.006
  """
  def fabrics, do: @fabrics

  @doc """
  The base of each layer: the distance of its cloth out of the body (dm),
  before the ease and the thickness of the fabric.

      iex> World.Sewing.layers()
      %{0 => 0.004, 1 => 0.03, 2 => 0.07, 3 => 0.15}
  """
  def layers, do: @layers

  @doc "The files of the garments: a list of `{file name, binary}` in `priv/makehuman/clothes/`."
  def files do
    Enum.flat_map(garments(), fn g ->
      %{obj: obj, fit: fit} = sew(g)
      [{g.name <> ".obj.gz", :zlib.gzip(obj)}, {g.name <> ".mhclo.gz", :zlib.gzip(fit)}, {g.name <> ".png", texture(g)}]
    end)
  end

  @doc """
  The entries of the garments in `assets.json` (as the entries of
  `scripts/makehuman.py`), with the layer, the shape (`[[target, weight]]`)
  and the drape (the points of the mesh that span the dips of the body,
  and the steps of the span of the fabric).
  """
  def entries do
    Map.new(garments(), fn g ->
      fabric = Map.fetch!(@fabrics, g.fabric)

      {g.name,
       %{
         "pack" => "world",
         "license" => "AGPL-3.0",
         "obj" => g.name <> ".obj.gz",
         "fit" => g.name <> ".mhclo.gz",
         "texture" => g.name <> ".png",
         "color" => List.duplicate(fabric.shade, 3),
         "transparent" => false,
         "layer" => g.layer,
         "fabric" => g.fabric,
         "shape" => Enum.map(g.shape, fn {t, w} -> [t, w] end),
         "drape" => if(fabric.span > 0, do: %{"points" => sew(g).drape, "steps" => fabric.span}, else: nil)
       }}
    end)
  end

  @doc """
  The heights (dm, the axes of MakeHuman) of the landmarks of the base
  mesh: the joints, the nipple and the line under the bust (the lowest
  point that the target `breast-point-decr` moves).

      iex> World.Sewing.landmarks().hip < World.Sewing.landmarks().waist
      true
  """
  def landmarks do
    Data.cached(:sewing_landmarks, fn ->
      %{points: points} = Data.base()
      y = fn g -> g |> joint() |> elem(1) end

      ys =
        for {v, d} <- Data.target("breast/breast-point-decr"), Vec.len(d) > 0.02, do: elem(elem(points, v), 1)

      %{
        head: y.("joint-head"),
        neck: y.("joint-neck"),
        waist: y.("joint-spine-3"),
        hip: y.("joint-l-upper-leg"),
        knee: y.("joint-l-knee"),
        ankle: y.("joint-l-ankle"),
        nipple:
          Data.target("breast/nipple-point-decr") |> Enum.map(fn {v, _} -> elem(elem(points, v), 1) end) |> mean(),
        underbust: Enum.min(ys)
      }
    end)
  end

  @doc """
  The seams of a garment: each pair of its pieces that share points, with
  the number of the points of the seam.
  """
  def seams(name) do
    g = Enum.find(garments(), &(&1.name == name)) || raise ArgumentError, "no garment #{name}"
    %{faces: faces, pieces: pieces} = cut(g)

    for f <- faces,
        names = f |> Enum.map(&Map.fetch!(pieces, elem(&1, 0))) |> Enum.reduce(&Enum.uniq(&1 ++ &2)),
        a <- names,
        b <- names,
        a < b,
        not Enum.all?(f, &(a in pieces[elem(&1, 0)])),
        not Enum.all?(f, &(b in pieces[elem(&1, 0)])),
        reduce: %{} do
      acc -> Map.update(acc, {a, b}, 1, &(&1 + 1))
    end
    |> Enum.map(fn {{a, b}, n} -> {a, b, n} end)
    |> Enum.sort()
  end

  # --- The cut ----------------------------------------------------------------

  # A garment sewn: its mesh (OBJ), its fit (MHCLO), and the points of the
  # mesh that drape (indices from 0, in the order of the mesh).
  defp sew(g) do
    Data.cached({:sewing, g.name}, fn ->
      %{points: points, uvs: uvs} = Data.base()
      fabric = Map.fetch!(@fabrics, g.fabric)
      %{faces: faces, pieces: of} = cut(g)
      by_name = Map.new(g.pieces, &{&1.name, &1})

      vs = points_of(faces) |> Enum.sort()
      index = vs |> Enum.with_index(1) |> Map.new()
      ts = faces |> Enum.flat_map(fn f -> Enum.map(f, &elem(&1, 1)) end) |> Enum.uniq() |> Enum.sort()
      tindex = ts |> Enum.with_index(1) |> Map.new()

      # The offset of each point: the mean over the pieces of the point
      # (a seam), along the normal of its surface.
      offsets = Map.new(vs, fn v -> {v, of[v] |> Enum.map(&offset(by_name[&1], v, g.layer, fabric)) |> Vec.mean()} end)
      drape = for v <- vs, Enum.any?(of[v], &by_name[&1][:drape]), do: Map.fetch!(index, v) - 1

      obj =
        IO.iodata_to_binary([
          "# The garment #{g.name} of World (World.Sewing).\n",
          for v <- vs do
            {x, y, z} = Vec.add(elem(points, v), Map.fetch!(offsets, v))
            ["v ", num(x), " ", num(y), " ", num(z), "\n"]
          end,
          for t <- ts do
            {u, w} = elem(uvs, t)
            ["vt ", num(u), " ", num(w), "\n"]
          end,
          "g #{g.name}\n",
          for f <- faces do
            ["f", for({v, t} <- f, do: [" ", Integer.to_string(index[v]), "/", Integer.to_string(tindex[t])]), "\n"]
          end
        ])

      fit =
        IO.iodata_to_binary([
          "# The fit of the garment #{g.name} of World to the base mesh hm08.\n",
          "name #{g.name}\nobj_file #{g.name}.obj\n",
          # The scales of male_casualsuit01 of MakeHuman: two points of the
          # body and their distance in the base mesh, for each axis.
          "x_scale 5399 11998 1.4340\nz_scale 962 5320 2.0001\ny_scale 791 881 2.4098\n",
          "verts 0\n",
          for v <- vs do
            {dx, dy, dz} = Map.fetch!(offsets, v)
            s = Integer.to_string(v)
            [s, " ", s, " ", s, " 1.0 0.0 0.0 ", num(dx), " ", num(dy), " ", num(dz), "\n"]
          end,
          "delete_verts\n",
          Enum.map(hidden(faces), &[Integer.to_string(&1), "\n"])
        ])

      %{obj: obj, fit: fit, drape: drape}
    end)
  end

  # The cut of a garment: its faces (the faces of each surface with each
  # point in a piece on that surface), and the pieces of each point.
  defp cut(g) do
    Data.cached({:sewing_cut, g.name}, fn ->
      %{groups: groups} = Data.base()

      g.pieces
      |> Enum.group_by(& &1.on)
      |> Enum.reduce(%{faces: [], pieces: %{}}, fn {on, pieces}, acc ->
        tests = Enum.map(pieces, &{&1.name, pattern(&1)})
        of = fn v -> for {name, inside?} <- tests, inside?.(v), do: name end
        faces = groups |> Map.fetch!(on) |> Enum.filter(fn f -> Enum.all?(f, &(of.(elem(&1, 0)) != [])) end)
        names = faces |> points_of() |> Map.new(&{&1, of.(&1)})
        %{faces: acc.faces ++ faces, pieces: Map.merge(acc.pieces, names)}
      end)
    end)
  end

  # The pattern of a piece: a test of a point of the base mesh.
  defp pattern(piece) do
    %{points: points} = Data.base()
    bone = dominant()
    {low, high} = Map.get(piece, :y, {nil, nil})
    low = level(low, -100.0)
    high = level(high, 100.0)
    cups = if piece[:region] == "cups", do: MapSet.new(Data.breast_points())
    {_, _, zc} = joint("joint-pelvis")
    {_, _, zs} = joint("joint-spine-2")
    arm = arm_axis()

    fn v ->
      {x, y, z} = p = elem(points, v)
      b = Map.get(bone, v)

      y >= low and y <= high and
        (piece.on != "body" or b in piece.bones) and
        (cups == nil or MapSet.member?(cups, v)) and
        (not Map.get(piece, :front, false) or z > zs) and
        in_x?(piece[:x], x) and
        in_angle?(piece[:angle], x, z - zc) and
        in_arm?(piece[:arm], b, p, arm)
    end
  end

  defp in_x?(nil, _x), do: true
  defp in_x?({a, b}, x), do: abs(x) >= a and abs(x) <= b

  # The panels: the angle around the pelvis, from the front (+z) or the back.
  defp in_angle?(nil, _x, _z), do: true

  defp in_angle?({side, half}, x, z) do
    a = abs(:math.atan2(x, z)) * 180 / :math.pi()
    if side == :front, do: a < half, else: a > 180 - half
  end

  # The sleeves: the part of the arm from the shoulder (0) to the wrist (1).
  defp in_arm?(nil, _b, _p, _axis), do: true

  defp in_arm?(part, b, {x, y, z}, {from, dir, len}) do
    if b in @arms do
      {fx, fy, fz} = from
      Vec.dot({abs(x) - fx, y - fy, z - fz}, dir) / len <= part
    else
      true
    end
  end

  # The axis of the left arm: from the shoulder to the hand (the right
  # arm is its mirror image).
  defp arm_axis do
    from = joint("joint-l-shoulder")
    d = Vec.sub(joint("joint-l-hand"), from)
    {from, Vec.norm(d), Vec.len(d)}
  end

  defp level(nil, default), do: default
  defp level({name, d}, _) when is_number(d), do: Map.fetch!(landmarks(), name) + d

  defp level({a, b, t}, _) do
    l = landmarks()
    l[a] + t * (l[b] - l[a])
  end

  # The offset of a point of a piece: along the normal of its surface, the
  # base of the layer, the ease (with the flare of pants, the room at the
  # hem, the baffles and the folded hood) and the thickness.
  defp offset(piece, v, layer, fabric) do
    %{points: points} = Data.base()
    {_, y, z} = elem(points, v)
    l = landmarks()
    {low, _} = Map.get(piece, :y, {nil, nil})
    hem = level(low, l.ankle)

    ease =
      case Map.get(piece, :ease, 0.0) do
        {:flare, top, bottom} ->
          t = min(1.0, max(0.0, (l.hip - y) / (l.hip - l.ankle)))
          top + (bottom - top) * t * t

        e ->
          e
      end

    room = Map.get(piece, :room, 0.0) * min(1.0, max(0.0, (hem + 1.0 - y) / 1.0))
    puff = Map.get(piece, :puff, 0.0) * (0.5 + 0.5 * :math.cos(2 * :math.pi() * y / @baffle))
    {_, _, nape} = joint("joint-neck")
    hood = Map.get(piece, :hood, 0.0)
    hood = if hood > 0 and y > l.neck - 0.4 and z < nape, do: hood * min(1.0, (y - l.neck + 0.4) / 0.6), else: 0.0

    Vec.scale(normal(piece.on, v), Map.fetch!(@layers, layer) + ease + room + puff + hood + fabric.thick)
  end

  # The points of the body inside a garment: each point under it with all
  # its neighbors under it (a point at an edge stays, so the body has no
  # hole at a hem, a cuff or a collar). Only the points of the body: a
  # panel on the skirt hides none.
  defp hidden(faces) do
    under = faces |> points_of() |> Enum.filter(&(&1 < @body)) |> MapSet.new()
    ring = neighbors()
    under |> Enum.filter(fn v -> Enum.all?(Map.get(ring, v, []), &MapSet.member?(under, &1)) end) |> Enum.sort()
  end

  defp mean(xs), do: Enum.sum(xs) / length(xs)

  defp points_of(faces), do: faces |> Enum.flat_map(fn f -> Enum.map(f, &elem(&1, 0)) end) |> Enum.uniq()

  # The mean of the points of a group of the base mesh (a joint).
  defp joint(g) do
    %{points: points, groups: groups} = Data.base()
    groups |> Map.fetch!(g) |> points_of() |> Enum.map(&elem(points, &1)) |> Vec.mean()
  end

  # The bone with the largest weight of each point of the body.
  defp dominant do
    Data.cached(:sewing_bones, fn ->
      for {bone, pairs} <- Data.weights(), [p, w] <- pairs, reduce: %{} do
        acc -> Map.update(acc, p, {bone, w}, fn {_, w0} = old -> if w > w0, do: {bone, w}, else: old end)
      end
      |> Map.new(fn {p, {bone, _}} -> {p, bone} end)
    end)
  end

  # The normal of a point of a surface: the sum of the normals of its
  # faces (each face is a quad: the cross of its diagonals), made a unit.
  defp normal(surface, v) do
    normals =
      Data.cached({:sewing_normals, surface}, fn ->
        %{points: points, groups: groups} = Data.base()

        groups
        |> Map.fetch!(surface)
        |> Enum.reduce(%{}, fn f, acc ->
          [a, b, c, d] = Enum.map(f, &elem(points, elem(&1, 0)))
          n = Vec.cross(Vec.sub(c, a), Vec.sub(d, b))
          Enum.reduce(f, acc, fn {v, _}, acc -> Map.update(acc, v, n, &Vec.add(&1, n)) end)
        end)
        |> Map.new(fn {v, n} -> {v, Vec.norm(n)} end)
      end)

    Map.fetch!(normals, v)
  end

  # The neighbors of each point of the body: the other points of its faces.
  defp neighbors do
    Data.cached(:sewing_ring, fn ->
      Data.base().groups
      |> Map.fetch!("body")
      |> Enum.reduce(%{}, fn f, acc ->
        vs = Enum.map(f, &elem(&1, 0))
        Enum.reduce(vs, acc, fn v, acc -> Map.update(acc, v, vs -- [v], &Enum.uniq(&1 ++ (vs -- [v]))) end)
      end)
    end)
  end

  # A number with 5 decimals, so the files are the same at each run.
  defp num(x), do: :erlang.float_to_binary(x / 1, decimals: 5)

  # A light texture of 128 x 128 texels: the shade of the fabric, with
  # the grain of its weave, the same bytes at each run. The color of an
  # order tints it.
  defp texture(g) do
    fabric = Map.fetch!(@fabrics, g.fabric)
    s = fabric.shade

    rows =
      for y <- 0..127 do
        for x <- 0..127, into: <<>> do
          d = if rem(x, fabric.grain) == 0 or rem(y, fabric.grain) == 0, do: -8, else: 0
          c = s + d + :erlang.phash2({x, y}, 7) - 3
          <<c, c, c>>
        end
      end

    World.PNG.encode(rows, 3)
  end
end
