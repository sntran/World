defmodule World.Site do
  @moduledoc """
  The days of a site (plan 0006, D1 and D2; `priv/standards/site.json`):
  the days of the work of a task, and the wait after it.

  - **The work of a task** is in the data of its node (`"work"`: a work
    of the rates to its amount, `{"concrete": 27.9, "formwork": 186}`),
    or comes from its takeoff (`World.Drawing.materials/3`: 70 bags of
    cement are 10 m3 of concrete), or is one task of an hour.
  - **The days** are the sum of each amount over the rate of its crew for
    the method of the site (`today` by default; `1974`, D6).
  - **The wait** (`"cure"` of the node: `lift`, `strip` or `set`) is the
    days that the tasks after it wait for the concrete to set.
  """
  alias World.Standards

  @methods ~w(today 1974)

  @doc "The methods of a site."
  def methods, do: @methods

  @doc "The works of the rates, in the order of their names."
  def works, do: Standards.names({"site", "rates"})

  @doc "The waits after a task (`\"cure\"` of a node)."
  def cures, do: Standards.names({"site", "cures"})

  @doc "The rate of a work for a method: `%{unit, crew, rate, source}` (the units in one day of the crew)."
  def rate(work, method \\ "today") when method in @methods do
    r = Standards.size({"site", "rates"}, work)
    %{unit: r["unit"], crew: r["crew"], rate: r[method], source: r["source"]}
  end

  @doc "The wait of a cure for a method, in days."
  def cure(name, method \\ "today") when method in @methods, do: Standards.size({"site", "cures"}, name)[method]

  @doc """
  The work of a takeoff: each material to its work (`"takeoff"` of the
  standards); a material with no work is no work.

      iex> World.Site.work_of(%{"cement" => 70, "brick" => 500, "glass" => 2})
      %{"concrete" => 9.99999, "brick" => 500.0}
  """
  def work_of(takeoff) do
    known = Standards.names({"site", "takeoff"})

    for {material, n} <- takeoff, material in known, reduce: %{} do
      acc ->
        %{"work" => w, "per" => per} = Standards.size({"site", "takeoff"}, material)
        Map.update(acc, w, n * per, &(&1 + n * per))
    end
  end

  @doc """
  The days of a work (`%{work => amount}`) for a method: the sum of each
  amount over its rate.

      iex> World.Site.days(%{"concrete" => 50.0})
      2.0
      iex> World.Site.days(%{"concrete" => 50.0}, "1974")
      12.5
  """
  def days(work, method \\ "today") do
    Enum.sum(for {w, amount} <- work, do: amount / rate(w, method).rate) / 1
  end

  @doc """
  The days and the wait of the task of a node of a drawing, with the
  data of the nodes it comes from (`World.Drawing.inputs/3`):
  `{days, wait}`. A node with no work in its data and no takeoff is one
  task of an hour (`"task"`).
  """
  def task(drawing, name, inputs, method \\ "today") do
    node = Enum.find(drawing["nodes"], &(&1["name"] == name))

    work =
      with nil <- node["work"] do
        case work_of(World.Drawing.materials(drawing, name, inputs)) do
          none when none == %{} -> %{"task" => 1}
          w -> w
        end
      end

    {days(work, method), wait(node, method)}
  end

  @doc """
  The schedule of a drawing on a site with no limit of people: the first
  and the last day of each task (`%{name => {first, last}}`, from day 0),
  each after the last day and the wait of each task it waits for
  (`World.Plan.of_drawing/1`). The work of a node is its data, or one
  task of an hour.
  """
  def schedule(drawing, method \\ "today") do
    tasks = Map.new(World.Plan.of_drawing(drawing).tasks, &{&1.id, &1})
    by_name = Map.new(drawing["nodes"], &{&1["name"], &1})

    Enum.reduce(World.Drawing.order(drawing), %{}, fn name, acc ->
      t = tasks[name]
      node = by_name[t.id]
      first = Enum.max([0.0 | for(w <- t.waits, do: elem(acc[w], 1) + wait(by_name[w], method))])
      Map.put(acc, t.id, {first, first + days(Map.get(node, "work") || %{"task" => 1}, method)})
    end)
  end

  defp wait(node, method), do: if(c = node["cure"], do: cure(c, method), else: 0.0)
end
