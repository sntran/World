defmodule World.ToySkills do
  @moduledoc """
  Two small skills for the tests of the skills (`World.Skill`): `block`
  (a mason lays a block of `size` m, as high as the blocks of its nodes
  `from` together, in `wait` ms: a test can pause it in hand) and `note` (a surveyor writes data, and makes no part).
  `test/test_helper.exs` adds them to `World.Skills`.
  """

  defmodule Block do
    @moduledoc "The skill `block`: a box of `size` m, with its ports `o` and `top`."
    @behaviour World.Skill
    alias World.{Part, Port, Shape}

    @impl true
    def name, do: "block"

    @impl true
    def trade, do: :mason

    @impl true
    def check(data, path) do
      case World.Skill.keys(data, path, ~w(size wait), ~w(size)) do
        [] ->
          if is_number(data["size"]) and data["size"] > 0, do: [], else: [{"#{path}.size", "must be a number over 0"}]

        errors ->
          errors
      end
    end

    @impl true
    def estimate(_data, _level), do: 12

    @impl true
    def make(%{"size" => s} = data, inputs, %{from: from}) do
      Process.sleep(Map.get(data, "wait", 0))
      h = s + Enum.sum(for name <- from, do: inputs[name]["size"] || 0)
      ports = [Port.new("o", {0.0, 0.0, 0.0}, {0, 0, 1}), Port.new("top", {0.0, 0.0, h / 1}, {0, 0, 1})]
      part = Part.new("block", :part, [Shape.box({-s / 2, -s / 2, 0.0}, {s / 2, s / 2, h / 1}, :concrete)], ports)
      {part, %{"size" => h}, %{"blocks" => [h]}}
    end
  end

  defmodule Note do
    @moduledoc "The skill `note`: data for the nodes that take it, and no part."
    @behaviour World.Skill

    @impl true
    def name, do: "note"

    @impl true
    def trade, do: :surveyor

    @impl true
    def check(data, path), do: World.Skill.keys(data, path, ~w(size))

    @impl true
    def estimate(_data, _level), do: 0

    @impl true
    def make(data, _inputs, _context), do: {nil, data, %{"noted" => true}}
  end
end
