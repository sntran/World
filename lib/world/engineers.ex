defmodule World.Engineers do
  @moduledoc """
  The engineers of the world (`docs/world.md`, step P9): a person, or a
  program that is a client of the MCP server (`World.MCP`), turns a
  request ("a bamboo chair") into a new drawing (`World.Drawing`) from the
  processes and the standard parts.

  1. `review/1`: the check of the drawing (each error with its path),
     then the checks of a true model (`World.Check`: it stands, no two
     parts are in one place, its joints are in their limits, it goes
     through the door of its workshop), its mass, its size and its parts.
  2. `propose/2`: a drawing that passes goes into the store as a
     proposal (`proposals/HASH.json`), with its request and its review.
  3. The owner reads the proposal (`mix world.review`), and accepts it
     (the drawing goes into `priv/drawings/`, and into the catalog with
     the next commit) or refuses it (nothing changes).

  A proposal is never a model of the catalog before the owner accepts it.
  """
  alias World.{Check, Drawing, Mass, Orders}
  alias World.Orders.Store

  @doc """
  The review of a drawing: `{:ok, review}` when the drawing and the model
  pass each check, else `{:error, review}`. The review has `errors` (of
  the data, `[{path, message}]` as maps), `checks` (the reasons of
  `World.Check`), `mass` (kg, and the parts with no mass), `size` (m),
  and `parts` (the count of each part).
  """
  def review(drawing) do
    case Drawing.check(drawing, "drawing") do
      {:ok, raw} ->
        model = World.Detail.with(:far, fn -> Drawing.build(raw) end)
        %{mass: mass, unknown: unknown} = Mass.of(model)
        checks = for reason <- reasons(Check.model(model)), do: Check.message(reason)
        placed = World.Build.placed(model)

        {{x0, y0, z0}, {x1, y1, z1}} =
          placed
          |> Enum.flat_map(fn {f, p} ->
            Enum.flat_map(p.shapes, &Enum.map(&1.points, fn pt -> World.Frame.point(f, pt) end))
          end)
          |> World.Vec.bounds()

        review = %{
          "name" => raw["name"],
          "errors" => [],
          "checks" => checks,
          "mass" => %{"kg" => Float.round(mass, 3), "unknown" => unknown},
          "size" => Enum.map([x1 - x0, y1 - y0, z1 - z0], &Float.round(&1, 3)),
          "parts" => Enum.frequencies_by(placed, fn {_, p} -> p.name end)
        }

        if checks == [] and unknown == [], do: {:ok, review}, else: {:error, review}

      {:error, errors} ->
        {:error, %{"errors" => for({p, m} <- errors, do: %{"path" => p, "message" => m})}}
    end
  end

  defp reasons(:ok), do: []
  defp reasons({:error, reasons}), do: reasons

  @doc """
  A proposal of a drawing for a request (a text of at most 2000 bytes):
  when its review passes, it goes into the store. `{:ok, %{"hash",
  "review"}}`, `{:error, review}` (the drawing does not pass: nothing goes
  into the store), or `{:error, :store}`.
  """
  def propose(drawing, request) when is_binary(request) and byte_size(request) in 1..2000 do
    with {:ok, review} <- review(drawing) do
      proposal = %{"request" => request, "drawing" => drawing, "review" => review}
      hash = Orders.hash(proposal)

      case Store.put_key(Store.proposal(hash), Orders.encode(proposal)) do
        :ok -> {:ok, %{"hash" => hash, "review" => review}}
        :error -> {:error, :store}
      end
    end
  end

  def propose(_drawing, _request),
    do: {:error, %{"errors" => [%{"path" => "request", "message" => "must be a text of 1 to 2000 bytes"}]}}

  @doc "The proposal of a hash: `{:ok, proposal}`, `:none` or `:error`."
  def proposal(hash) do
    with true <- is_binary(hash) and hash =~ ~r/^[0-9a-f]{32}$/,
         {:ok, json} <- Store.get_key(Store.proposal(hash)) do
      {:ok, JSON.decode!(json)}
    else
      :error -> :error
      _ -> :none
    end
  end

  @doc """
  The owner accepts a proposal: its drawing goes to `dir/NAME.json`
  (`priv/drawings` for the catalog). A drawing of that name in the folder
  stays: `{:error, :exists}`.
  """
  def accept(%{"drawing" => %{"name" => name} = drawing}, dir) do
    path = Path.join(dir, name <> ".json")

    if File.exists?(path) do
      {:error, :exists}
    else
      File.mkdir_p!(dir)
      File.write!(path, [:json.format(drawing), "\n"])
      {:ok, path}
    end
  end
end
