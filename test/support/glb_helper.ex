defmodule World.GLBHelper do
  @moduledoc "Reads the JSON chunk of a GLB, for the tests."

  def json(<<"glTF", 2::little-32, total::little-32, len::little-32, "JSON", json::binary-size(len), _::binary>> = glb) do
    true = byte_size(glb) == total
    JSON.decode!(json)
  end

  @doc "The values of an accessor of floats: a tuple for each element."
  def floats(
        <<"glTF", 2::little-32, _::little-32, len::little-32, "JSON", _::binary-size(len), rest::binary>> = glb,
        index
      ) do
    <<_::little-32, "BIN", 0, bin::binary>> = rest
    json = json(glb)
    a = Enum.at(json["accessors"], index)
    view = Enum.at(json["bufferViews"], a["bufferView"])
    size = %{"SCALAR" => 1, "VEC2" => 2, "VEC3" => 3, "VEC4" => 4}[a["type"]]
    data = binary_part(bin, Map.get(view, "byteOffset", 0) + Map.get(a, "byteOffset", 0), a["count"] * size * 4)
    values = for <<x::little-float-32 <- data>>, do: x
    values |> Enum.chunk_every(size) |> Enum.map(&List.to_tuple/1)
  end
end
