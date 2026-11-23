defmodule World.Tint do
  @moduledoc """
  The tint of a copy (plan 0020, D1): a color `#rrggbb` that multiplies
  the color of each part of the copy. A copy in a copy with a tint has
  the product of the two tints.
  """

  @doc "The tint of a copy in a copy: the product of the two (nil: no tint)."
  def mix(nil, nil), do: nil
  def mix(nil, tint), do: String.downcase(tint)
  def mix(tint, nil), do: String.downcase(tint)

  def mix(a, b) do
    {ra, ga, ba} = rgb(a)
    {rb, gb, bb} = rgb(b)
    hex({round(ra * rb / 255), round(ga * gb / 255), round(ba * bb / 255)})
  end

  @doc "The tint in linear values from 0 to 1, as `COLOR_0` of glTF (nil is white)."
  def linear(nil), do: {1.0, 1.0, 1.0}

  def linear(tint) do
    {r, g, b} = rgb(tint)
    {to_linear(r / 255), to_linear(g / 255), to_linear(b / 255)}
  end

  defp rgb("#" <> hex) do
    <<r::binary-2, g::binary-2, b::binary-2>> = hex
    {String.to_integer(r, 16), String.to_integer(g, 16), String.to_integer(b, 16)}
  end

  defp hex({r, g, b}),
    do:
      "#" <> Enum.map_join([r, g, b], &(&1 |> Integer.to_string(16) |> String.pad_leading(2, "0") |> String.downcase()))

  defp to_linear(c) when c <= 0.04045, do: Float.round(c / 12.92, 5)
  defp to_linear(c), do: Float.round(:math.pow((c + 0.055) / 1.055, 2.4), 5)
end
