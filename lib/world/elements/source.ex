defmodule World.Elements.Source do
  @moduledoc """
  The version of a rule from its source (`World.Elements.version/1`): the
  files of the modules that the rule names, again and again, each with its
  path from the root of the project, the data files that those modules
  read, and the versions of Elixir and Erlang/OTP.

  It is not a hash of the compiled modules. The code of some modules has
  the path of the folder of the build (an attribute with `__DIR__`), and
  the compiler gives some names in the order of the compile. So two
  builds of one commit in two folders give the same version, and the key
  of a part is the same in the factory, in a construction shift, in a job
  of CI and in a clone on a computer (`mix world.order`).

  The read of the source (`analyze/2`) gives, for each file:

  - of `lib` (`.ex`): the modules that it defines; the modules that it
    calls (in a function, or in the body of the module, which runs at
    the compile), whose struct it uses, or that it takes with `require`,
    `import` or `use`, with its aliases (a module that is only a value,
    as an entry of a list of skills, is not a part of the rule); and the
    files of `priv` that it reads (a
    path of `Path.join/1,2`, `Path.expand/2`, `Path.wildcard/1` or
    `:code.priv_dir/1` with the segment `priv`, in a function, in
    `@external_resource` or in an attribute that is not the base of
    another path);
  - of `wings` (`.erl`): the module of `-module`, the modules of its
    calls, and the files of `-include`.

  A version changes when one of its files changes, and not when another
  file changes. A name that is not a module of the source (`Enum`,
  `:lists`) is not followed, and a module of the service
  (`service?/1`) is not followed.
  """

  @typedoc "The result of `analyze/2`."
  @type manifest :: %{
          digests: %{String.t() => binary()},
          modules: %{module() => String.t()},
          refs: %{String.t() => [module()]},
          data: %{String.t() => [String.t()]}
        }

  # The modules that are not a part of a rule: the service, the store, the
  # line of the builds, the gate of the memory of a build, and the keys of
  # the parts themselves (each with the modules in it); and the module
  # `World` (the census and the memory of the VM), with no module in it.
  @service ~w(Orders Elements Construction Service MCP Engineers Log Line Guard Files Stream Supervisor Application Sculpt.Gate)
           |> Enum.map(&"Elixir.World.#{&1}")

  @doc "True for a module of World that is not a part of a rule (the service, the store, the keys)."
  def service?(World), do: true

  def service?(module) do
    name = Atom.to_string(module)
    Enum.any?(@service, &(name == &1 or String.starts_with?(name, &1 <> ".")))
  end

  @doc """
  The read of the files `paths` under `root` (paths from `root`, as
  `World.Crew.Source.files/1` gives them).
  """
  @spec analyze(String.t(), [String.t()]) :: manifest()
  def analyze(root, paths) do
    digests = Map.new(paths, &{&1, :erlang.md5(File.read!(Path.join(root, &1)))})

    reads =
      for path <- paths, String.ends_with?(path, [".ex", ".erl"]), into: %{} do
        {path, read(path, File.read!(Path.join(root, path)), paths)}
      end

    modules = for {path, r} <- reads, m <- r.modules, into: %{}, do: {m, path}

    %{
      digests: digests,
      modules: modules,
      refs: Map.new(reads, fn {path, r} -> {path, r.refs |> resolve(modules, path) |> Enum.sort()} end),
      data: Map.new(reads, fn {path, r} -> {path, r.data |> files_under(paths) |> Enum.sort()} end)
    }
  end

  @doc """
  The files of the version of `module`: its file, the file of each module
  that it names, again and again, and the data files of each of them.
  """
  @spec files(manifest(), module()) :: [String.t()]
  def files(manifest, module), do: walk([module], manifest, MapSet.new([module]), MapSet.new())

  @doc "The version of `module` (12 hexadecimal characters)."
  @spec version(manifest(), module()) :: String.t()
  def version(manifest, module) do
    lines = for f <- files(manifest, module), do: [f, ?\t, Base.encode16(manifest.digests[f], case: :lower), ?\n]
    runtime = ["elixir ", System.version(), "\notp ", List.to_string(:erlang.system_info(:otp_release)), ?\n]
    :crypto.hash(:md5, [lines, runtime]) |> Base.encode16(case: :lower) |> binary_part(0, 12)
  end

  defp walk([], _manifest, _seen, files), do: Enum.sort(files)

  defp walk([module | rest], manifest, seen, files) do
    case manifest.modules[module] do
      nil ->
        walk(rest, manifest, seen, files)

      file ->
        files = files |> MapSet.put(file) |> MapSet.union(MapSet.new(manifest.data[file]))
        same = for {m, ^file} <- manifest.modules, do: m
        next = (same ++ manifest.refs[file]) |> Enum.uniq() |> Enum.reject(&(MapSet.member?(seen, &1) or service?(&1)))
        walk(rest ++ next, manifest, MapSet.union(seen, MapSet.new(next)), files)
    end
  end

  # The data files of a list of paths of `priv` (a file, or each file of a folder).
  defp files_under(prefixes, paths) do
    for p <- prefixes, path <- paths, path == p or String.starts_with?(path, p <> "/"), uniq: true, do: path
  end

  # The module of each name: the first that is a module of the source (not of the file itself).
  defp resolve(candidates, modules, path) do
    for names <- candidates,
        m = Enum.find(names, &Map.has_key?(modules, &1)),
        modules[m] != path,
        uniq: true,
        do: m
  end

  ## The read of one file

  defp read(path, text, paths) do
    if String.ends_with?(path, ".erl"), do: read_erl(path, text, paths), else: read_ex(text)
  end

  defp read_erl(path, text, paths) do
    module =
      case Regex.run(~r/^-module\(([a-z0-9_]+)\)\./m, text) do
        [_, name] -> String.to_atom(name)
        nil -> path |> Path.basename(".erl") |> String.to_atom()
      end

    includes =
      for [_, name] <- Regex.scan(~r/^-include(?:_lib)?\("([^"]+)"\)\./m, text),
          other <- paths,
          Path.basename(other) == Path.basename(name),
          uniq: true,
          do: other

    calls =
      for [_, m] <- Regex.scan(~r/\b([a-z][a-z0-9_]*):[a-z][a-zA-Z0-9_]*\(/, text), uniq: true, do: [String.to_atom(m)]

    %{modules: [module], refs: calls, data: includes}
  end

  defp read_ex(text) do
    {:ok, ast} = Code.string_to_quoted(text, columns: false, emit_warnings: false)
    state = scope(ast, nil, %{}, %{modules: [], refs: [], data: [], attrs: %{}, paths: %{}, bases: MapSet.new()})
    # (The path of an attribute, unless it is the base of another path.)
    kept = for {key, path} <- state.paths, not MapSet.member?(state.bases, key), do: path
    %{modules: Enum.reverse(state.modules), refs: state.refs, data: Enum.uniq(kept ++ state.data)}
  end

  # The forms of a module body (or of the file, out of a module).
  defp scope(ast, module, aliases, state) do
    forms = block(ast)
    # (The aliases of a body hold for all of it, also an alias in a
    # function: a name too many is safe. A module in the body has its own.)
    aliases = Enum.reduce(forms, aliases, &alias_of(&1, module, &2))
    aliases = Enum.reduce(forms, aliases, &inner_aliases(&1, module, &2))
    Enum.reduce(forms, state, &form(&1, module, aliases, &2))
  end

  defp inner_aliases({:defmodule, _, _}, _module, aliases), do: aliases

  defp inner_aliases(form, module, aliases) do
    {_, aliases} =
      Macro.prewalk(form, aliases, fn
        {:defmodule, _, _}, aliases -> {nil, aliases}
        {:alias, _, _} = node, aliases -> {nil, alias_of(node, module, aliases)}
        node, aliases -> {node, aliases}
      end)

    aliases
  end

  defp block({:__block__, _, forms}), do: forms
  defp block(form), do: [form]

  defp form({:defmodule, _, [name, [do: body]]}, parent, aliases, state) do
    module = module_name(name, parent)
    inner = scope(body, module, aliases, %{state | modules: [module | state.modules], attrs: %{}})
    # (A module in a module has its own attributes; the module around it keeps its own.)
    %{inner | attrs: state.attrs}
  end

  defp form({:alias, _, _}, _module, _aliases, state), do: state

  # (A doc or a type is not code of the rule.)
  defp form({:@, _, [{name, _, _}]}, _module, _aliases, state)
       when name in [:doc, :moduledoc, :typedoc, :type, :typep, :opaque, :spec, :callback, :macrocallback] do
    state
  end

  # (An attribute: its path is a data file, unless another path takes it as its base.)
  defp form({:@, _, [{name, _, [value]}]}, module, aliases, state) when name != :external_resource do
    state =
      case path_call(value) do
        nil ->
          collect(value, module, aliases, state)

        {fun, args} ->
          {pieces, bases} = pieces(value, state)
          state = state |> mark(bases, module) |> collect_args(args, module, aliases)
          state = if fun == :wildcard or pieces != [], do: put_path(state, {module, name}, pieces), else: state
          state
      end

    # (The parts of its path now: in a new value, `@name` is the value before.)
    %{state | attrs: Map.put(state.attrs, name, pieces_of(value, state))}
  end

  defp form(other, module, aliases, state), do: collect(other, module, aliases, state)

  defp collect_args(state, args, module, aliases), do: Enum.reduce(args, state, &collect(&1, module, aliases, &2))

  # Each name of a module and each path of `priv` in an expression.
  defp collect(ast, module, aliases, state) do
    {_, state} =
      Macro.prewalk(ast, state, fn
        {:defmodule, _, [_, [do: _]]} = node, state ->
          {nil, form(node, module, aliases, state)}

        {:alias, _, _}, state ->
          {nil, state}

        {:@, _, [{:external_resource, _, [value]}]}, state ->
          {value, add(value, module, state)}

        {kind, _, [{:__aliases__, _, parts} | _]} = node, state when kind in [:require, :import, :use] ->
          {node, ref(state, parts, module, aliases)}

        {:%, _, [{:__aliases__, _, parts}, _]} = node, state ->
          {node, ref(state, parts, module, aliases)}

        {{:., _, [{:__aliases__, _, [:Path]}, fun]}, _, _} = node, state when fun in [:join, :expand, :wildcard] ->
          {node, add(node, module, state)}

        {{:., _, [{:__aliases__, _, parts}, fun]}, _, _} = node, state when is_atom(fun) ->
          {node, ref(state, parts, module, aliases)}

        {{:., _, [erl, _fun]}, _, _} = node, state when is_atom(erl) and erl not in [nil, true, false] ->
          {node, %{state | refs: [[erl] | state.refs]}}

        node, state ->
          {node, state}
      end)

    state
  end

  # (A module that the code calls, whose struct it uses, or that it takes
  # with require, import or use. A module that is only a value, as an
  # entry of a list of skills, is not a part of the rule.)
  defp ref(state, parts, module, aliases), do: %{state | refs: [candidates(parts, module, aliases) | state.refs]}

  defp add(ast, module, state) do
    {pieces, bases} = pieces(ast, state)
    state = mark(state, bases, module)

    case priv_path(pieces) do
      nil -> state
      path -> %{state | data: [path | state.data]}
    end
  end

  defp put_path(state, key, pieces) do
    case priv_path(pieces) do
      nil -> state
      path -> %{state | paths: Map.put(state.paths, key, path)}
    end
  end

  defp mark(state, bases, module), do: %{state | bases: Enum.reduce(bases, state.bases, &MapSet.put(&2, {module, &1}))}

  defp path_call({:=, _, [_, right]}), do: path_call(right)

  defp path_call({{:., _, [{:__aliases__, _, [:Path]}, fun]}, _, args}) when fun in [:join, :expand, :wildcard],
    do: {fun, args}

  defp path_call(_), do: nil

  # The literal parts of a path, to the first part that is not literal,
  # and the attributes that it takes as its base.
  defp pieces(ast, state) do
    {parts, bases} = ast |> pieces_of(state) |> Enum.split_with(&(not match?({:base, _}, &1)))
    {Enum.take_while(parts, &(&1 != :stop)), for({:base, name} <- bases, do: name)}
  end

  defp pieces_of(text, _state) when is_binary(text), do: [text]
  defp pieces_of(list, state) when is_list(list), do: Enum.flat_map(list, &pieces_of(&1, state))
  defp pieces_of({:__DIR__, _, ctx}, _state) when is_atom(ctx), do: []
  defp pieces_of({{:., _, [:code, :priv_dir]}, _, _}, _state), do: [:priv]
  defp pieces_of({:<>, _, [left, _]}, state), do: pieces_of(left, state) ++ [:stop]
  defp pieces_of({:<<>>, _, parts}, _state), do: Enum.take_while(parts, &is_binary/1) ++ [:stop]
  defp pieces_of({:=, _, [_, right]}, state), do: pieces_of(right, state)

  defp pieces_of({{:., _, [{:__aliases__, _, [:Path]}, fun]}, _, args}, state)
       when fun in [:join, :expand, :wildcard] do
    if fun == :expand, do: pieces_of(hd(args), state), else: pieces_of(args, state)
  end

  defp pieces_of({:@, _, [{name, _, ctx}]}, state) when is_atom(ctx) do
    case state.attrs do
      %{^name => parts} -> [{:base, name} | parts]
      _ -> [:stop]
    end
  end

  defp pieces_of(_, _state), do: [:stop]

  # The path in `priv` of the parts of a path ("../../priv/a" and "b/*.json" give "priv/a/b").
  defp priv_path(pieces) do
    segments =
      pieces
      |> Enum.flat_map(fn
        :priv -> ["priv"]
        text -> String.split(text, "/", trim: true)
      end)
      |> Enum.reject(&(&1 in [".", ".."]))
      |> Enum.take_while(&(not String.contains?(&1, ["*", "{", "?"])))

    case Enum.drop_while(segments, &(&1 != "priv")) do
      ["priv" | rest] -> Enum.join(["priv" | rest], "/")
      [] -> nil
    end
  end

  # The names that an alias can be: with the aliases of the module, in
  # the modules around it, and as it is.
  defp candidates(parts, module, aliases) do
    parts =
      Enum.map(parts, fn
        {:__MODULE__, _, ctx} when is_atom(ctx) -> :__MODULE__
        p -> p
      end)

    cond do
      not Enum.all?(parts, &is_atom/1) -> []
      hd(parts) == :__MODULE__ and module != nil -> [Module.concat([module | tl(parts)])]
      hd(parts) == :__MODULE__ -> []
      true -> names(parts, module, aliases)
    end
  end

  defp names([head | rest] = parts, module, aliases) do
    from_alias = for base <- List.wrap(aliases[head]), do: Module.concat([base | rest])
    around = for m <- outer(module), do: Module.concat([m | parts])
    from_alias ++ around ++ [Module.concat(parts)]
  end

  defp outer(nil), do: []

  defp outer(module) do
    parts = Module.split(module)
    for n <- length(parts)..1//-1, do: Module.concat(Enum.take(parts, n))
  end

  defp alias_of({:alias, _, [target | opts]}, module, aliases) do
    as = opts |> List.first() |> List.wrap() |> Keyword.get(:as)

    case target do
      {{:., _, [{:__aliases__, _, base}, :{}]}, _, names} ->
        base = Module.concat(expand(base, module, aliases))

        for {:__aliases__, _, parts} <- names,
            reduce: aliases,
            do: (a -> Map.put(a, List.last(parts), Module.concat([base | parts])))

      {:__aliases__, _, parts} ->
        full = Module.concat(expand(parts, module, aliases))

        case as do
          {:__aliases__, _, as_parts} -> Map.put(aliases, List.last(as_parts), full)
          _ -> Map.put(aliases, List.last(parts), full)
        end

      _ ->
        aliases
    end
  end

  # (A module in a module: its last name is an alias in the body around it.)
  defp alias_of({:defmodule, _, [{:__aliases__, _, [name]} = alias, _]}, module, aliases) when is_atom(name),
    do: Map.put(aliases, name, module_name(alias, module))

  defp alias_of(_form, _module, aliases), do: aliases

  defp expand([{:__MODULE__, _, _} | rest], module, _aliases), do: [module | rest]

  defp expand([head | rest] = parts, _module, aliases) do
    case aliases[head] do
      nil -> parts
      base -> [base | rest]
    end
  end

  defp module_name({:__aliases__, _, [{:__MODULE__, _, _} | rest]}, parent), do: Module.concat([parent | rest])
  defp module_name({:__aliases__, _, parts}, nil), do: Module.concat(parts)
  defp module_name({:__aliases__, _, parts}, parent), do: Module.concat([parent | parts])
  defp module_name(name, _parent) when is_atom(name), do: name
end

defmodule World.Elements.Sources do
  @moduledoc """
  The read of the source of World (`World.Elements.Source.analyze/2`)
  when this module was compiled: the MD5 of each file with its path from
  the root, the file of each module, the modules that each file names,
  and the data files that it reads. Mix compiles this module again when a
  file of the source changes, comes or goes.
  """
  alias World.Crew.Source, as: Files
  alias World.Elements.Source

  @root Path.expand("../../..", __DIR__)
  @paths Files.files(@root)
  for path <- @paths, do: @external_resource(Path.join(@root, path))
  @manifest Source.analyze(@root, @paths)

  @doc "The read of the source."
  def get, do: @manifest

  @doc false
  def __mix_recompile__?, do: Files.files(@root) != @paths
end
