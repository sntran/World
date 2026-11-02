defmodule World.People.Kit do
  @moduledoc """
  The kit of a person (`docs/factory.md`, "The kit of a person"): the
  parts of the parked traveler of `World.People.traveler/3` at mid, as
  static files, so that a viewer (the profile of Phượt) shows each change
  of the body, the hair, the eyes, the skin and the clothes at once, with
  no build:

  - `person/woman.glb`, `person/man.glb`: the body of each sex with its
    shape targets, eyes, eyebrows, skeleton and animations
    (`World.People.Human.kit/3`);
  - `person/SEX-hair-NAME.glb`: each hair on the skeleton of each sex;
  - `skins/NAME.jpg`, `eyes/NAME.png`: the textures of the skins and the
    eyes;
  - `kit.json`: the names of the files, the clothes, and the place of the
    person next to each vehicle (and each van of the camper).

  The viewer finds the weights of the targets from the numbers of the
  person as `World.People.Human.target_weights/1`, moves the bones, gives
  each face of the body the color of the clothes that cover it, and puts
  the person down by the ground of its shoes (the extras `kit` of the
  mesh of a body).
  """
  alias World.GLB
  alias World.People
  alias World.People.{Data, Human}

  @sexes [{"woman", 0}, {"man", 1}]

  # A parked person faces +x of World: a turn of -90 degrees around the
  # up axis (y of glTF), as `World.People.traveler/3` at a vehicle.
  @turn [0.0, -0.70711, 0.0, 0.70711]

  @doc "The files of the kit: a list of `{path, binary}`, with the paths in the folder of the kit."
  def files do
    bodies = for {sex, g} <- @sexes, do: {"person/#{sex}.glb", glb(Human.kit(g, :body))}

    hair =
      for {sex, g} <- @sexes, name <- hair(), do: {"person/#{sex}-hair-#{name}.glb", glb(Human.kit(g, {:hair, name}))}

    textures =
      for({name, path} <- textures("skins"), do: {"skins/#{name}#{Path.extname(path)}", File.read!(path)}) ++
        for {name, path} <- textures("eye_materials"), do: {"eyes/#{name}#{Path.extname(path)}", File.read!(path)}

    [{"kit.json", JSON.encode!(manifest())} | bodies ++ hair ++ textures]
  end

  @doc """
  The data of `kit.json`: the files of the bodies and of the hair, the
  textures of the skins and the eyes, the clothes, and the place of a
  parked person (`translation` in the axes of glTF, and `rotation`, a
  quaternion) next to each vehicle and each van of the camper.
  """
  def manifest do
    vans = World.Vehicles.Van.models()

    %{
      "version" => 1,
      "level" => "mid",
      "people" => Map.new(@sexes, fn {sex, _} -> {sex, "person/#{sex}.glb"} end),
      "hair" =>
        Map.new(hair(), fn name ->
          {name, Map.new(@sexes, fn {sex, _} -> {sex, "person/#{sex}-hair-#{name}.glb"} end)}
        end),
      "skins" => Map.new(textures("skins"), fn {name, path} -> {name, "skins/#{name}#{Path.extname(path)}"} end),
      "eyes" => Map.new(textures("eye_materials"), fn {name, path} -> {name, "eyes/#{name}#{Path.extname(path)}"} end),
      "clothes" => Data.assets()["clothes"] |> Map.keys() |> Enum.sort(),
      "rotation" => @turn,
      "places" => Map.new(People.vehicles() -- ["camper"], &{&1, place(&1, nil)}),
      "vans" => Map.new(vans, &{&1, place("camper", &1)})
    }
  end

  defp place(vehicle, van) do
    {x, y} = People.place(vehicle, van)
    {a, b, c} = GLB.gl({x, y, 0.0})
    [a / 1, b / 1, c / 1]
  end

  defp hair, do: Data.assets()["hair"] |> Map.keys() |> Enum.sort()

  defp textures(kind) do
    for name <- Data.assets()[kind] |> Map.keys() |> Enum.sort(),
        path = Data.asset(kind, name).texture,
        path != nil,
        do: {name, path}
  end

  defp glb(figure), do: World.Build.glb(figure, level: :mid)
end
