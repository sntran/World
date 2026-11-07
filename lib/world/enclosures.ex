defmodule World.Enclosures do
  @moduledoc """
  The enclosures of the sheet metal shop (`docs/world.md`, step P6; the
  trade `sheet_metal_worker`): boxes of steel sheet for electrical gear, each an
  assembly of the kind `:enclosure`, from `World.Sheet`.

  - `hoffman_a16n126/0`: the nVent HOFFMAN A-16N126, a wall-mount box of
    NEMA Type 1 with a hinged cover, 16 by 12 by 6 in.
  """
  alias World.{Assembly, Frame, Kit, Part, Sheet}
  alias World.Materials.Stock
  import Kit, only: [inch: 1]

  @o Part.port("o", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})

  # The gray powder coat of the enclosures of the A line (ANSI 61; the
  # color is near it, by eye).
  @gray %{"color" => [142, 150, 150], "roughness" => 0.45, "metalness" => 0.05}

  @doc "The models of the enclosures, as `{name, fun}`."
  def models, do: [{"enclosure_hoffman_a16n126", &__MODULE__.hoffman_a16n126/0}]

  @doc """
  The nVent HOFFMAN A-16N126 (bulletin A1SM): a box of NEMA Type 1 of
  mild steel, gray, 16 in high, 12 in wide and 6 in deep, with a cover on
  two butt hinges, a latch, and mounting holes in the back (Kele, Border
  States). The listings do not give its gauge: 16 gauge, as the A12N128
  of the same line (Lumen). The lips of the body (1/2 in), the flanges of
  the cover (1/2 in), the holes, the hinges and the latch: by eye.

  The back is at y = -3 in, the cover at the front (+y); x across, z up.
  """
  def hoffman_a16n126 do
    {w, h, d} = {inch(12), inch(16), inch(6)}
    t = Stock.gauge("16")
    {lip, gap} = {inch(0.5), 0.001}

    # The body: the back (12 by 16 in) and four sides of 6 in, each with
    # a lip to the inside at the front, and four mounting holes.
    hole = inch(0.3)

    holes =
      for x <- [inch(1.5), w - inch(1.5) - hole], z <- [inch(1.5), h - inch(1.5) - hole], do: {x, z, x + hole, z + hole}

    body =
      [:left, :right, :front, :back]
      |> Enum.reduce(Sheet.new(w, h, t, material: :paint, matter: :steel), &Sheet.flange(&2, &1, d, lip: lip))
      |> then(fn s -> Enum.reduce(holes, s, &Sheet.hole(&2, &1)) end)
      # The sheet: x across, y up, its flanges to the front.
      |> Sheet.part("body_a16n126", :box, [@o],
        frame: Frame.new({w / 2, -d / 2, 0.0}, {0, 1, 0}, {0, 0, 1}),
        sources: [
          "The body of the A-16N126: 12 by 16 by 6 in (Kele: Small Type 1 Enclosure, A1SM, 16.00x12.00x6.00, steel, gray); steel of 16 gauge (as the A12N128, Lumen); the lips and the holes by eye."
        ]
      )

    # The cover: a pan over the front, its flanges to the back, outside
    # the sides of the body.
    {cw, ch} = {w + 2 * (t + gap), h + 2 * (t + gap)}
    front = d / 2 + gap + t

    cover =
      [:left, :right, :front, :back]
      |> Enum.reduce(Sheet.new(cw, ch, t, material: :paint, matter: :steel), &Sheet.flange(&2, &1, lip))
      |> Sheet.part("cover_a16n126", :door, [hinge_port({-cw / 2, front - lip, 0.0})],
        frame: Frame.new({-cw / 2, front, -(t + gap)}, {0, -1, 0}, {0, 0, 1}),
        sources: [
          "The cover of the A-16N126: a pan of steel of 16 gauge on butt hinges (Kele: removable doors with butt hinges); its flanges by eye."
        ]
      )

    latch =
      Kit.knob("latch_a16n126", {cw / 2 - inch(1), front, h / 2}, {0, 1, 0}, {0, 0, 1}, inch(0.3), inch(0.4), :metal)

    Assembly.new("enclosure_hoffman_a16n126", body,
      root: "body",
      kind: :enclosure,
      materials: %{paint: @gray},
      sources: [
        "nVent HOFFMAN A-16N126, a wall-mount enclosure of NEMA Type 1, 16 by 12 by 6 in (Kele, Border States, Crescent Electric)."
      ]
    )
    |> Assembly.add("cover", cover,
      at: hinge_port({-cw / 2, front - lip, 0.0}),
      port: "hinge",
      kind: :hinge,
      role: :door,
      limits: [0, 110]
    )
    |> Assembly.add_all(hinges({-cw / 2, front - lip}, h))
    |> Assembly.add("latch", latch,
      to: "cover",
      at: Kit.same("latch_a16n126", {cw / 2 - inch(1), front, h / 2}, {0, 1, 0}, {0, 0, 1}),
      port: "latch_a16n126"
    )
  end

  # The axis of the hinges: up the left back edge of the flange of the
  # cover. The cover opens to the left (+ angle).
  defp hinge_port(at), do: Part.port("hinge", at, {0, 0, 1}, {0, 1, 0})

  # Two butt hinges of steel of 1 1/2 in (by eye), as on a real box: the
  # pin on the axis of the cover, the fixed half on the body (its leaf to
  # the back, -y), the moving half on the cover (its leaf to the front).
  defp hinges({x, y}, h) do
    {fixed, moving} =
      World.Materials.Construction.butt_hinge("butt_hinge_a16n126", inch(1.5), inch(0.45), 0.003,
        knuckles: 3,
        t: 0.0015,
        sources: [
          "A butt hinge of steel of 1 1/2 in, its leaves 0.45 in, inside the flange of the cover (1/2 in): by eye."
        ]
      )

    for {z, k} <- Enum.with_index([inch(2.5), h - inch(4)], 1),
        # The leaf of a hinge goes along x of its port: here along y.
        at <- [Part.port("hinge_#{k}", {x, y, z}, {0, 0, 1}, {-1, 0, 0})],
        node <- [
          {"hinge_#{k}", fixed, [at: at, port: "pin"]},
          {"hinge_leaf_#{k}", moving, [to: "cover", at: at, port: "pin"]}
        ],
        do: node
  end
end
