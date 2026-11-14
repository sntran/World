defmodule World.People.Parts do
  @moduledoc """
  The parts of a person from edits
  (`docs/plans/0017-people-with-parts-from-edits.md`): hair as a mass, a
  nón lá, a helmet. Each part is a sculpture of the catalog (a drawing
  of edits with maps) with the port `crown` at the top of the head, and
  a person wears it on its port `crown` (the option `wear` of
  `World.People.Human.person/2`).

  The body, the face and the skeleton of the person stay those of
  MakeHuman: the field of edits is for the forms that a mesh with cards
  does not make well.

  | Part | What it is | Fits the head |
  |---|---|---|
  | `non_la_edits` | A nón lá with its rings, the ring for the head and its strap | No: one size |
  | `mu_bao_hiem_edits` | A half helmet of a rider with its peak and its straps | Yes |
  | `toc_ngan_edits` | Short hair | Yes |
  | `toc_bui_edits` | Hair in a bun | Yes |
  | `toc_dai_edits` | Long hair to the shoulders (one piece: it turns with the head) | Yes |

  A part that fits the head has the size of the head of its person: it
  is drawn on the head of the woman of the catalog (16.4 cm wide with
  the ears, 18.8 cm long with the nose), and it grows by the mean of the
  two ratios of a larger head. The image of the hair is light: the
  color of its role is the color of the hair of the person.
  """
  alias World.Vec

  @parts %{
    "non_la_edits" => false,
    "mu_bao_hiem_edits" => true,
    "toc_ngan_edits" => true,
    "toc_bui_edits" => true,
    "toc_dai_edits" => true
  }
  # The width and the length of the head that the parts are drawn on (m).
  @head {0.164, 0.188}

  @doc "The names of the parts."
  def names, do: @parts |> Map.keys() |> Enum.sort()

  @doc "The port of a person that a part goes on."
  def on(name) when is_map_key(@parts, name), do: "crown"

  @doc """
  The scale of a part for a head of a width and a length (m): 1 for a
  part of one size, and for the head that the parts are drawn on.
  """
  def scale(name, {width, length}) when is_map_key(@parts, name) do
    {w, l} = @head
    if @parts[name], do: (width / w + length / l) / 2, else: 1.0
  end

  @doc """
  A part by its name, at the level of detail of the work: an assembly
  with the port `crown`. The options: `scale` (the part grows from its
  port by this), and `color` (`[r, g, b]`: the color of its role, a tint
  of its image; for the hair, the color of the hair).
  """
  def part(name, opts \\ []) do
    unless is_map_key(@parts, name),
      do: raise(ArgumentError, "unknown part #{inspect(name)}: #{Enum.join(names(), ", ")}")

    item = World.Drawing.file(name)
    scale = Keyword.get(opts, :scale, 1.0)

    nodes =
      for {node, part, connection} <- item.nodes do
        {node,
         %{part | shapes: Enum.map(part.shapes, fn m -> %{m | points: Enum.map(m.points, &Vec.scale(&1, scale))} end)},
         connection}
      end

    materials =
      case opts[:color] do
        nil -> item.materials
        color -> Map.new(item.materials, fn {role, material} -> {role, Map.put(material, "color", color)} end)
      end

    %{item | nodes: nodes, materials: materials}
  end
end
