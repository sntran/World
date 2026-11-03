defmodule World.Turned do
  @moduledoc """
  The parts that the turnery of the world turns on its lathe
  (`World.Lathe`, `docs/world.md` step P2): a tea cup and a rice bowl of
  Bát Tràng porcelain, a beer bottle of glass, a baluster of a balcony of
  concrete, and a pot of terracotta for a plant. Each profile is in meters
  (`{r, z}`: the distance from the axis and the height), with its sources.
  """
  alias World.Lathe

  @doc """
  The names of the turned parts, and the function of each.

      iex> World.Turned.names()
      ["chen_tra", "bat_com", "bottle_longneck_355ml", "baluster_con_tien", "pot_terracotta_8in"]
  """
  def names, do: Enum.map(models(), &elem(&1, 0))

  @doc "The turned parts: a list of `{name, fun}` for the catalog."
  def models do
    [
      {"chen_tra", &chen_tra/0},
      {"bat_com", &bat_com/0},
      {"bottle_longneck_355ml", &bottle/0},
      {"baluster_con_tien", &baluster/0},
      {"pot_terracotta_8in", &pot/0}
    ]
  end

  @doc """
  A small tea cup (chén trà) of Bát Tràng porcelain: 6 cm across the
  rim, 4 cm high, on a small foot.
  """
  def chen_tra do
    Lathe.turn(
      "chen_tra",
      [{0.0, 0.0}, {0.014, 0.0}, {0.0155, 0.004}, {0.018, 0.0055}, {0.024, 0.013}, {0.028, 0.025}, {0.03, 0.04}],
      :porcelain,
      wall: 0.0025,
      floor: 0.004,
      sources: [
        "A chén of Bát Tràng: 6 cm across the mouth and 4 cm high (a set of tử sa, Lazada, https://www.lazada.vn/videodetail/?video_id=30064644093).",
        "The foot, the curve and the wall of 2.5 mm: by eye from photos of chén trà of Bát Tràng."
      ]
    )
  end

  @doc """
  A rice bowl (bát cơm) of Bát Tràng porcelain: 11.5 cm across the rim, 6
  cm high, on a foot ring of 5 cm.
  """
  def bat_com do
    Lathe.turn(
      "bat_com",
      [
        {0.0, 0.0},
        {0.024, 0.0},
        {0.0255, 0.006},
        {0.03, 0.0085},
        {0.042, 0.019},
        {0.051, 0.034},
        {0.0565, 0.05},
        {0.0575, 0.06}
      ],
      :porcelain,
      wall: 0.0035,
      floor: 0.005,
      sources: [
        "A bát cơm of Bát Tràng: 11.5 x 6 cm (chiaki.vn, https://chiaki.vn/bat-gom-su-cao-cap-vien-may-kieu-non-hoa-tiet-doc-dao).",
        "The foot ring, the curve and the wall of 3.5 mm: by eye from photos of bát cơm of Bát Tràng."
      ]
    )
  end

  @doc """
  A beer bottle of amber glass, the US standard longneck of 12 fl oz
  (355 ml): 23.1 cm high, 6.1 cm across, with a crown finish of 26 mm.
  """
  def bottle do
    Lathe.turn(
      "bottle_longneck_355ml",
      [
        {0.0, 0.0},
        {0.0275, 0.0},
        {0.0305, 0.004},
        {0.0305, 0.108},
        {0.029, 0.118},
        {0.0225, 0.142},
        {0.0148, 0.17},
        {0.0125, 0.2},
        {0.0123, 0.219},
        {0.0133, 0.222},
        {0.0133, 0.229},
        {0.0125, 0.231}
      ],
      :glass_amber,
      wall: 0.0016,
      floor: 0.005,
      sources: [
        "A 12 oz long neck beer bottle: 9.09 in (23.1 cm) high, 2.4 in (6.1 cm) across, 355 ml (https://www.dimensions.com/element/beer-bottle-12-oz-long-neck).",
        "The crown cap of a longneck: 26 mm. The shoulder and the neck: by eye from photos of the bottle. The wall of 1.6 mm gives the mass of a real bottle: 0.425 lb (193 g) for a 12 oz amber longneck (Kaufman Container, https://www.kaufmancontainer.com/12-oz-amber-glass-beer-bottle-bulk/)."
      ]
    )
  end

  @doc """
  A baluster of a balcony (con tiện lục bình) of concrete: 60 cm high, a
  vase of 12 cm at its belly and 6 cm at its neck, a ring of 11 cm at
  each end. With two of them 16 cm apart (center to center), the gap is
  10 cm at the necks and 4 cm at the bellies: under the 4 in (10.2 cm)
  of a guard.
  """
  def baluster do
    Lathe.turn(
      "baluster_con_tien",
      [
        {0.0, 0.0},
        {0.055, 0.0},
        {0.055, 0.03},
        {0.046, 0.04},
        {0.034, 0.06},
        {0.05, 0.12},
        {0.06, 0.2},
        {0.058, 0.25},
        {0.042, 0.34},
        {0.03, 0.45},
        {0.032, 0.5},
        {0.046, 0.54},
        {0.055, 0.57},
        {0.055, 0.6}
      ],
      :concrete,
      sources: [
        "A con tiện lục bình of a balcony of Việt Nam: by eye from photos (60 cm high, a belly of 12 cm, a neck of 6 cm).",
        "A guard: no gap for a sphere of 4 in (10.2 cm) (IRC R312.1.3)."
      ]
    )
  end

  @doc """
  A standard pot of terracotta for a plant: 8 in (20.3 cm) across its rim
  and 8 in high, with a rim band of 2.5 cm.
  """
  def pot do
    Lathe.turn(
      "pot_terracotta_8in",
      [
        {0.0, 0.0},
        {0.068, 0.0},
        {0.07, 0.004},
        {0.088, 0.17},
        {0.1, 0.176},
        {0.1016, 0.18},
        {0.1016, 0.2032}
      ],
      :terracotta,
      wall: 0.009,
      floor: 0.01,
      sources: [
        "A standard pot of terracotta of 8 in: 8.25 in across and 8 in high (Mother Plants, https://gardenista.com/products/cylinder-pots); 8 in and 8 in (Deroma).",
        "The foot of 14 cm, the rim band and the wall of 9 mm: by eye from photos of standard pots."
      ]
    )
  end
end
