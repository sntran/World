defmodule Xuong.Port do
  @moduledoc """
  A place where a part connects to another part: a point, its main
  direction (`axis`: the axis of a hole, a shaft, a thread) and a second
  direction at a right angle (`up`). When two ports connect, the two
  points are at the same place, and the two axes and the two `up`
  directions are the same.
  """
  alias Xuong.{Frame, Vec}

  defstruct name: "port", at: {0.0, 0.0, 0.0}, axis: {0.0, 0.0, 1.0}, up: {0.0, 1.0, 0.0}

  def new(name, at, axis, up \\ nil) do
    up = up || Vec.cross(axis, Vec.perpendicular(axis))
    %__MODULE__{name: name, at: Vec.float(at), axis: Vec.norm(Vec.float(axis)), up: Vec.norm(Vec.float(up))}
  end

  @doc "The frame of the port: its z is the axis, its y is `up`."
  def frame(%__MODULE__{at: at, axis: axis, up: up}), do: Frame.new(at, axis, up)
end

defmodule Xuong.Part do
  @moduledoc """
  A part: its meshes, its ports, its numbers and the sources of its
  sizes. `docs/format.md`, "A part".

  - `detail`: `nil` (the size of the part decides its levels),
    `:always` (it stays at each level: a light of a vehicle), `:near`
    (only the near level), or `:low` (only mid and far: a part that
    stands in for many small parts, not in the list of the parts).
  - `inside`: a part that a body hides (a bolt in a frame, a bearing in a
    hub): only the near level.
  """
  alias Xuong.{Mesh, Port, Vec}

  defstruct name: "part",
            kind: :part,
            params: %{},
            sources: [],
            ports: %{},
            shapes: [],
            detail: nil,
            inside: false,
            print: :keep

  @doc """
  A part. `ports` is a list of `Xuong.Port`; `opts` are the other fields.
  """
  def new(name, kind, shapes, ports, opts \\ []) do
    struct!(
      __MODULE__,
      [name: name, kind: kind, shapes: List.wrap(shapes), ports: Map.new(ports, &{&1.name, &1})] ++ opts
    )
  end

  @doc "A port of the part, by its name."
  def port!(%__MODULE__{ports: ports, name: name}, port) do
    Map.get(ports, port) || raise ArgumentError, "the part #{name} has no port #{inspect(port)}"
  end

  @doc "The box of the meshes of the part: `{min, max}`."
  def bounds(%__MODULE__{shapes: shapes}), do: shapes |> Enum.flat_map(& &1.points) |> Vec.bounds()

  @doc "The same part with each mesh in one material."
  def paint(%__MODULE__{shapes: shapes} = p, material),
    do: %{p | shapes: Enum.map(shapes, fn %Mesh{} = m -> %{m | material: material} end)}

  @doc "The same part with a new name."
  def rename(%__MODULE__{} = p, name), do: %{p | name: name}

  @doc "The same part with more ports."
  def with_ports(%__MODULE__{ports: ports} = p, more), do: %{p | ports: Map.merge(ports, Map.new(more, &{&1.name, &1}))}

  @doc "A port at a point of the part, as `Xuong.Port.new/4`."
  def port(name, at, axis, up \\ nil), do: Port.new(name, at, axis, up)
end
