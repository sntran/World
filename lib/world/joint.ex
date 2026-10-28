defmodule World.Joint do
  @moduledoc """
  A joint: how a thing moves on the thing that holds it. The same model
  for a door on a van, a wheel on an axle, and an elbow of a person.

  - `kind`:
    - `:hinge`: it turns around one axis (a door, a wheel, an elbow, a
      knee), in degrees;
    - `:slide`: it moves along one axis (a drawer, the tube of a fork),
      in meters;
    - `:ball`: it turns around three axes (a shoulder, a hip, the neck):
      `flex`, `spread` and `twist`, in degrees.
  - `axes`: the names of its values: `[nil]` for a hinge or a slide (the
    value has the name of the joint), `[:flex, :spread, :twist]` for a
    ball (the value of each axis has the name `joint.axis`).
  - `limits`: `{min, max}` of the value (nil: no limit, a wheel), or a
    map of an axis to its `{min, max}` for a ball.
  - `role`: what the joint is for (`:door`, `:wheel`, `:elbow`).
  - `bone`: for a joint of a person, the bone that turns.

  An order gives the values of the joints of a model in `"joints"`, by
  their names (`values/1`): `"hood": 50`, `"elbow_l": 90`,
  `"shoulder_l.spread": 40`.
  """

  defstruct name: nil, kind: :hinge, axes: [nil], limits: nil, role: nil, bone: nil

  @type t :: %__MODULE__{}

  @kinds [:hinge, :slide, :ball]
  @ball [:flex, :spread, :twist]

  @doc "A joint. `kind` is `:hinge`, `:slide` or `:ball`."
  def new(name, kind, opts \\ []) when kind in @kinds do
    axes = if kind == :ball, do: @ball, else: [nil]
    struct!(__MODULE__, [name: name, kind: kind, axes: axes] ++ opts)
  end

  @doc "The names of the values of a joint, for an order."
  def values(%__MODULE__{name: name, axes: axes}), do: for(a <- axes, do: if(a, do: "#{name}.#{a}", else: name))

  @doc """
  The limits of a value of the joint (`nil` for the one value of a hinge
  or a slide, else an axis of a ball): `{min, max}`, or nil.
  """
  def limits(%__MODULE__{limits: %{} = limits}, axis), do: Map.get(limits, axis)
  def limits(%__MODULE__{limits: [lo, hi]}, nil), do: {lo, hi}
  def limits(%__MODULE__{limits: limits}, nil), do: limits

  @doc """
  The value in the limits of the joint. A value out of the limits stops
  at the nearest limit, as a real joint stops.
  """
  def clamp(%__MODULE__{} = j, axis, value) do
    case limits(j, axis) do
      nil -> value
      {lo, hi} -> value |> max(lo) |> min(hi)
    end
  end

  @doc "The extras of a joint in a GLB node, for the apps and the review page."
  def extras(%__MODULE__{} = j) do
    limits =
      case j.limits do
        %{} = m -> Map.new(m, fn {axis, {lo, hi}} -> {Atom.to_string(axis), [lo, hi]} end)
        {lo, hi} -> [lo, hi]
        other -> other
      end

    %{"kind" => Atom.to_string(j.kind), "role" => j.role && Atom.to_string(j.role), "limits" => limits}
  end
end
