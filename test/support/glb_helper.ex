defmodule Xuong.GLBHelper do
  @moduledoc "Reads the JSON chunk of a GLB, for the tests."

  def json(<<"glTF", 2::little-32, total::little-32, len::little-32, "JSON", json::binary-size(len), _::binary>> = glb) do
    true = byte_size(glb) == total
    JSON.decode!(json)
  end
end
