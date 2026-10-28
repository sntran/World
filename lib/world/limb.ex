defmodule World.Limb do
  @moduledoc """
  A limb: a named chain of bones of a skeleton, from the root of the
  limb to its end, and the way to put the end at a point (inverse
  kinematics). The end of a limb is the tail of its last bone: the wrist
  for an arm (the upper arm and the forearm), the ankle for a leg.

  - `solver`:
    - `:two_bone`: two bones and a hinge in the middle (an arm, a leg).
      The hinge bends as much as it must (the law of cosines), then the
      first bone turns to the point, with the hinge to the side of
      `pole`. Exact.
    - `:chain`: any count of bones (a spine, a finger, a tail, the leg of
      a dog). Each bone turns in turn, from the end to the root, so that
      the end goes to the point (cyclic coordinate descent), 48 times: a
      few millimeters from a point that the chain can reach.
  - `pole`: for `:two_bone`, the side of the hinge, in the axes of the
    figure at rest.
  - `role`: what the limb is (`:arm`, `:leg`, `:spine`, `:finger`).
  """

  defstruct name: nil, bones: [], solver: :two_bone, pole: {0.0, 0.0, 1.0}, role: nil

  @type t :: %__MODULE__{}

  @doc "A limb: its name, its bones from the root to the end, and the options of the struct."
  def new(name, bones, opts \\ []), do: struct!(__MODULE__, [name: name, bones: bones] ++ opts)
end
