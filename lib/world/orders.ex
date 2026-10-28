defmodule World.Orders do
  @moduledoc """
  The factory (`docs/factory.md`): an order in, the files of a model out.

  An order is a map (from JSON):

  - `"blueprint"`: the name of a blueprint (`World.Orders.Blueprints`);
  - `"options"`: the options of the blueprint;
  - `"colors"`: a color `#rrggbb` for a material role (`"paint"`);
  - `"joints"`: the value of a joint at rest, in degrees or meters
    (`{"hood": 50}`).

  `check/1` gives the full order: each option with its value, and the
  keys in one order. `hash/1` is the name of its files: the same order
  gives the same hash, and the same files.
  """
  alias World.{Build, Detail, GLB, Log, Run}
  alias World.Orders.{Blueprint, Blueprints}
  @keys ~w(blueprint options colors joints)
  @levels %{"near" => :near, "mid" => :mid, "far" => :far}
  @files ~w(glb log replay parts receipt)

  @doc "The names of the levels of detail."
  def levels, do: Map.keys(@levels) |> Enum.sort()

  @doc """
  Check an order. Gives `{:ok, order}`, the full order, or `{:error,
  errors}`: each error is a map with its `"path"` and its `"message"`.
  """
  def check(order) when is_map(order) do
    case full(order) do
      {:ok, full} -> {:ok, full}
      {:error, errors} -> {:error, for({path, message} <- errors, do: %{"path" => path, "message" => message})}
    end
  end

  def check(_order), do: {:error, [%{"path" => "", "message" => "must be an object"}]}

  defp full(order) do
    unknown = for key <- Enum.sort(Map.keys(order)), key not in @keys, do: {key, "is not a key of an order"}

    with [] <- unknown,
         {:ok, blueprint} <- blueprint(order["blueprint"]),
         {:ok, options} <- Blueprint.check_options(blueprint.options, Map.get(order, "options", %{}), "options"),
         [] <- if(blueprint.check, do: blueprint.check.(options), else: []),
         {:ok, colors} <- colors(Map.get(order, "colors", %{})),
         {:ok, joints} <- joints(Map.get(order, "joints", %{})) do
      {:ok, %{"blueprint" => blueprint.name, "options" => options, "colors" => colors, "joints" => joints}}
    else
      errors when is_list(errors) -> {:error, errors}
      {:error, errors} -> {:error, errors}
    end
  end

  defp blueprint(name) do
    case Blueprints.fetch(name) do
      {:ok, b} -> {:ok, b}
      :error -> {:error, [{"blueprint", "must be one of: #{Enum.join(Blueprints.names(), ", ")}"}]}
    end
  end

  defp colors(colors) when is_map(colors) do
    roles = GLB.palette() |> Map.keys() |> Enum.sort()
    color = Blueprint.option("color", :color)

    errors =
      Enum.flat_map(Enum.sort(colors), fn {role, c} ->
        if role in roles,
          do: elem_errors(Blueprint.value(color, c, "colors.#{role}")),
          else: [{"colors.#{role}", "must be a role: #{Enum.join(roles, ", ")}"}]
      end)

    if errors == [], do: {:ok, Map.new(colors, fn {k, v} -> {k, String.downcase(v)} end)}, else: {:error, errors}
  end

  defp colors(_), do: {:error, [{"colors", "must be an object"}]}

  defp joints(joints) when is_map(joints) do
    errors =
      for {name, v} <- Enum.sort(joints), not is_number(v), do: {"joints.#{name}", "must be a number"}

    if errors == [], do: {:ok, Map.new(joints, fn {k, v} -> {k, v / 1} end)}, else: {:error, errors}
  end

  defp joints(_), do: {:error, [{"joints", "must be an object"}]}

  defp elem_errors({:ok, _}), do: []
  defp elem_errors({:error, errors}), do: errors

  @doc "The hash of a full order: 32 hex digits of its SHA-256."
  def hash(order), do: :crypto.hash(:sha256, encode(order)) |> Base.encode16(case: :lower) |> binary_part(0, 32)

  @doc """
  The JSON of a value with the keys of each object in order: the same
  value gives the same bytes.
  """
  def encode(map) when is_map(map) do
    pairs =
      for {k, v} <- Enum.sort_by(map, fn {k, _} -> to_string(k) end), do: [JSON.encode!(to_string(k)), ?:, encode(v)]

    IO.iodata_to_binary([?{, Enum.intersperse(pairs, ?,), ?}])
  end

  def encode(list) when is_list(list),
    do: IO.iodata_to_binary([?[, Enum.intersperse(Enum.map(list, &encode/1), ?,), ?]])

  def encode(value), do: JSON.encode!(value)

  @doc "The files of an order."
  def files, do: @files

  @doc """
  Build a file of an order at a level (`"near"`, `"mid"` or `"far"`). The
  files (`files/0`):

  - `"glb"`: the model. The people of the world build it (`World.Run`):
    the foreman makes the files with the pose and the colors of the order.
  - `"log"`: the log of a run of the order, in JSON (`World.Log`).
  - `"replay"`: the model with each part in a node of its own, with the id
    of its task, for the replay of the log.
  - `"parts"`: the list of the parts. `"receipt"`: the receipt.

  Gives `{:ok, binary}`, or `{:error, errors}` as `check/1`.
  """
  def build(order, level, file) do
    with {:ok, order} <- check(order),
         {:ok, lvl} <- level(level),
         :ok <- file(file) do
      {:ok, blueprint} = Blueprints.fetch(order["blueprint"])
      item = Detail.with(lvl, fn -> blueprint.build.(order["options"]) end)

      scene = fn opts ->
        s = Build.scene(item, [level: lvl, pose: order["joints"]] ++ opts)
        %{s | materials: Map.merge(s.materials, materials(order["colors"]))}
      end

      with :ok <- joints(order, scene) do
        {:ok, make(file, order, lvl, item, scene)}
      end
    end
  end

  defp make("glb", order, _lvl, item, scene), do: elem(world(order, item, scene), 0)
  defp make("log", order, _lvl, item, scene), do: elem(world(order, item, scene), 1)
  defp make("replay", _order, _lvl, _item, scene), do: GLB.encode(scene.(split: true))
  defp make("parts", _order, _lvl, item, _scene), do: parts(item)
  defp make("receipt", order, lvl, _item, scene), do: receipt(order, lvl, scene.([]))

  # A run of the world for the order: the files of the model and the log.
  defp world(order, item, scene) do
    run = Run.start()
    {:ok, result} = Run.order(run, item, hash(order), files: fn _ -> GLB.encode(scene.([])) end)
    log = Run.log(run)
    Run.stop(run)
    {result.glb, Log.to_json(log)}
  end

  # A joint of the order must be a joint of the model.
  defp joints(%{"joints" => joints}, _scene) when joints == %{}, do: :ok

  defp joints(%{"joints" => joints}, scene) do
    known = scene.([]).extras["joints"]

    case for name <- Enum.sort(Map.keys(joints)), name not in known, do: name do
      [] ->
        :ok

      bad ->
        {:error,
         for(name <- bad, do: %{"path" => "joints.#{name}", "message" => "is not a joint: #{Enum.join(known, ", ")}"})}
    end
  end

  defp file(file) do
    if file in @files,
      do: :ok,
      else: {:error, [%{"path" => "file", "message" => "must be one of: #{Enum.join(@files, ", ")}"}]}
  end

  defp level(name) do
    case Map.fetch(@levels, name) do
      {:ok, l} -> {:ok, l}
      :error -> {:error, [%{"path" => "level", "message" => "must be one of: #{Enum.join(levels(), ", ")}"}]}
    end
  end

  # A color of an order keeps the roughness and the metalness of its role.
  defp materials(colors) do
    Map.new(colors, fn {role, "#" <> hex} ->
      <<r::8, g::8, b::8>> = Base.decode16!(hex, case: :lower)
      {String.to_existing_atom(role), Map.put(GLB.palette()[role], "color", [r, g, b])}
    end)
  end

  defp parts(item), do: encode(%{"name" => item.name, "parts" => Build.parts(item)})

  defp receipt(order, level, scene) do
    encode(%{
      "order" => order,
      "hash" => hash(order),
      "level" => Atom.to_string(level),
      "world" => to_string(Application.spec(:world, :vsn)),
      "name" => scene.extras["name"],
      "kind" => scene.extras["kind"],
      "size" => scene.extras["size"],
      "joints" => scene.extras["joints"],
      "sources" => scene.extras["sources"]
    })
  end
end
