defmodule ElixirSense.Core.MetadataBuilder do
  @moduledoc """
  This module is responsible for building/retrieving environment information from an AST.
  """

  import ElixirSense.Core.State
  alias ElixirSense.Core.Ast
  alias ElixirSense.Core.State
  alias ElixirSense.Core.State.VarInfo

  @scope_keywords [:for, :try, :fn]
  @block_keywords [:do, :else, :rescue, :catch, :after]
  @defs [:def, :defp, :defmacro, :defmacrop, :defdelegate, :defguard, :defguardp]

  defguard is_call(call, params)
           when is_atom(call) and is_list(params) and
                  call not in [:., :__aliases__, :"::", :{}, :|>]

  @doc """
  Traverses the AST building/retrieving the environment information.
  It returns a `ElixirSense.Core.State` struct containing the information.
  """
  def build(ast) do
    {_ast, state} = Macro.traverse(ast, %State{}, &pre/2, &post/2)
    state
  end

  defp pre_module(ast, state, position, module) do
    state
    |> maybe_add_protocol_implementation(module)
    |> new_namespace(module)
    |> add_current_module_to_index(position)
    |> new_attributes_scope
    |> new_behaviours_scope
    |> new_alias_scope
    |> new_import_scope
    |> new_require_scope
    |> new_vars_scope
    |> result(ast)
  end

  defp post_module(ast, state, module) do
    state
    |> remove_attributes_scope
    |> remove_behaviours_scope
    |> remove_alias_scope
    |> remove_import_scope
    |> remove_require_scope
    |> remove_vars_scope
    |> remove_module_from_namespace(module)
    |> remove_protocol_implementation
    |> result(ast)
  end

  defp pre_func(ast = {type, _, _}, state, %{line: line, col: col}, name, params) do
    state
    |> new_named_func(name, length(params || []))
    |> add_func_to_index(name, params || [], {line, col}, type)
    |> new_alias_scope
    |> new_import_scope
    |> new_require_scope
    |> new_func_vars_scope
    |> add_vars(find_vars(params), true)
    |> add_current_env_to_line(line)
    |> result(ast)
  end

  defp post_func(ast, state) do
    state
    |> remove_alias_scope
    |> remove_import_scope
    |> remove_require_scope
    |> remove_func_vars_scope
    |> remove_last_scope_from_scopes
    |> result(ast)
  end

  defp pre_scope_keyword(ast, state, line) do
    state
    |> add_current_env_to_line(line)
    |> new_vars_scope
    |> result(ast)
  end

  defp post_scope_keyword(ast, state) do
    state
    |> remove_vars_scope
    |> result(ast)
  end

  defp pre_block_keyword(ast, state) do
    state
    |> new_alias_scope
    |> new_import_scope
    |> new_require_scope
    |> new_vars_scope
    |> result(ast)
  end

  defp post_block_keyword(ast, state) do
    state
    |> remove_alias_scope
    |> remove_import_scope
    |> remove_require_scope
    |> remove_vars_scope
    |> result(ast)
  end

  defp pre_clause(ast = {_, [line: line, column: _column], _}, state, lhs) do
    state
    |> new_alias_scope
    |> new_import_scope
    |> new_require_scope
    |> new_vars_scope
    |> add_vars(find_vars(lhs), true)
    |> add_current_env_to_line(line)
    |> result(ast)
  end

  defp post_clause(ast, state) do
    state
    |> remove_alias_scope
    |> remove_import_scope
    |> remove_require_scope
    |> remove_vars_scope
    |> result(ast)
  end

  defp pre_alias(ast, state, line, aliases_tuples) when is_list(aliases_tuples) do
    state
    |> add_current_env_to_line(line)
    |> add_aliases(aliases_tuples)
    |> result(ast)
  end

  defp pre_alias(ast, state, line, alias_tuple) do
    state
    |> add_current_env_to_line(line)
    |> add_alias(alias_tuple)
    |> result(ast)
  end

  defp pre_import(ast, state, line, modules) when is_list(modules) do
    state
    |> add_current_env_to_line(line)
    |> add_imports(modules)
    |> result(ast)
  end

  defp pre_import(ast, state, line, module) do
    state
    |> add_current_env_to_line(line)
    |> add_import(module)
    |> result(ast)
  end

  defp pre_require(ast, state, line, modules) when is_list(modules) do
    state
    |> add_current_env_to_line(line)
    |> add_requires(modules)
    |> result(ast)
  end

  defp pre_require(ast, state, line, module) do
    state
    |> add_current_env_to_line(line)
    |> add_require(module)
    |> result(ast)
  end

  defp pre_module_attribute(ast, state, line, name) do
    state
    |> add_current_env_to_line(line)
    |> add_attribute(name)
    |> result(ast)
  end

  defp pre_behaviour(ast, state, line, module) do
    state
    |> add_current_env_to_line(line)
    |> add_behaviour(module)
    |> result(ast)
  end

  defp post_string_literal(ast, state, line, str) do
    str
    |> String.split(["\n", "\r\n"])
    |> Enum.with_index()
    |> Enum.reduce(state, fn {_s, i}, acc -> add_current_env_to_line(acc, line + i) end)
    |> result(ast)
  end

  defp pre(
         {:defmodule, _, [{:__aliases__, [line: line, column: column], module}, _]} = ast,
         state
       ) do
    pre_module(ast, state, {line, column}, module)
  end

  defp pre(
         {:defprotocol, _, [{:__aliases__, [line: line, column: column], module}, _]} = ast,
         state
       ) do
    pre_module(ast, state, {line, column}, module)
  end

  defp pre(
         {:defimpl, _,
          [{:__aliases__, [line: line, column: column], protocol}, [for: implementations], _]} =
           ast,
         state
       ) do
    case implementations do
      list when is_list(list) ->
        modules =
          list
          |> Enum.map(fn {:__aliases__, _, implementation} ->
            implementation
          end)

        pre_module(ast, state, {line, column}, {protocol, modules})

      {:__aliases__, _, implementation} ->
        pre_module(ast, state, {line, column}, {protocol, [implementation]})
    end
  end

  defp pre({def_name, meta, [{:when, _, [head | _]}, body]}, state) when def_name in @defs do
    pre({def_name, meta, [head, body]}, state)
  end

  defp pre({def_name, meta, [{name, [line: line, column: column] = meta2, params}, body]}, state)
       when def_name in @defs and is_atom(name) do
    ast_without_params = {def_name, meta, [{name, add_no_call(meta2), []}, body]}
    pre_func(ast_without_params, state, %{line: line, col: column}, name, params)
  end

  # defguard and defguardp
  defp pre(
         {def_name, meta,
          [
            {:when, [line: _, column: _],
             [{name, [line: line, column: column] = meta2, params}, body]}
          ]},
         state
       )
       when def_name in [:defguard, :defguardp] do
    ast_without_params = {def_name, meta, [{name, add_no_call(meta2), []}, body]}
    pre_func(ast_without_params, state, %{line: line, col: column}, name, params)
  end

  # protocol function
  defp pre({def_name, meta, [{name, [line: line, column: column] = meta2, params}]}, state)
       when def_name == :def do
    ast_without_params = {def_name, meta, [{name, add_no_call(meta2), []}, nil]}
    pre_func(ast_without_params, state, %{line: line, col: column}, name, params)
  end

  defp pre({def_name, _meta, _} = ast, state) when def_name in @defs do
    {ast, state}
  end

  defp pre(
         {:@, [line: line, column: _column], [{:behaviour, _, [{:__aliases__, _, module_atoms}]}]} =
           ast,
         state
       ) do
    module = module_atoms |> Module.concat()
    pre_behaviour(ast, state, line, module)
  end

  defp pre({:@, [line: line, column: _column], [{:behaviour, _, [erlang_module]}]} = ast, state) do
    pre_behaviour(ast, state, line, erlang_module)
  end

  defp pre({:@, [line: line, column: _column] = meta_attr, [{name, meta, params}]}, state) do
    new_ast = {:@, meta_attr, [{name, add_no_call(meta), params}]}
    pre_module_attribute(new_ast, state, line, name)
  end

  # import with v1.2 notation
  defp pre(
         {:import, [line: line, column: _column],
          [{{:., _, [{:__aliases__, _, prefix_atoms}, :{}]}, _, imports}]} = ast,
         state
       ) do
    imports_modules =
      imports
      |> Enum.map(fn {:__aliases__, _, mods} ->
        Module.concat(prefix_atoms ++ mods)
      end)

    pre_import(ast, state, line, imports_modules)
  end

  # import without options
  defp pre({:import, meta, [module_info]}, state) do
    pre({:import, meta, [module_info, []]}, state)
  end

  # import with options
  defp pre(
         {:import, [line: line, column: _column], [{_, _, module_atoms = [mod | _]}, _opts]} =
           ast,
         state
       )
       when is_atom(mod) do
    module = module_atoms |> Module.concat()
    pre_import(ast, state, line, module)
  end

  # erlang module
  defp pre({:import, [line: line, column: _column], [atom] = ast}, state) when is_atom(atom) do
    pre_import(ast, state, line, atom)
  end

  # require with v1.2 notation
  defp pre(
         {:require, [line: line, column: _column],
          [{{:., _, [{:__aliases__, _, prefix_atoms}, :{}]}, _, requires}]} = ast,
         state
       ) do
    requires_modules =
      requires
      |> Enum.map(fn {:__aliases__, _, mods} ->
        Module.concat(prefix_atoms ++ mods)
      end)

    pre_require(ast, state, line, requires_modules)
  end

  # require without options
  defp pre({:require, meta, [module_info]}, state) do
    pre({:require, meta, [module_info, []]}, state)
  end

  # require with `as` option
  defp pre(
         {:require, [line: line, column: _column],
          [{_, _, module_atoms = [mod | _]}, [as: {:__aliases__, _, alias_atoms = [al | _]}]]} =
           ast,
         state
       )
       when is_atom(mod) and is_atom(al) do
    alias_tuple = {Module.concat(alias_atoms), Module.concat(module_atoms)}
    module = module_atoms |> Module.concat()
    {_, new_state} = pre_alias(ast, state, line, alias_tuple)
    pre_require(ast, new_state, line, module)
  end

  # require erlang module with `as` option
  defp pre(
         {:require, [line: line, column: _column],
          [mod, [as: {:__aliases__, _, alias_atoms = [al | _]}]]} = ast,
         state
       )
       when is_atom(mod) and is_atom(al) do
    alias_tuple = {Module.concat(alias_atoms), mod}
    {_, new_state} = pre_alias(ast, state, line, alias_tuple)
    pre_require(ast, new_state, line, mod)
  end

  # require with options
  defp pre(
         {:require, [line: line, column: _column], [{_, _, module_atoms = [mod | _]}, _opts]} =
           ast,
         state
       )
       when is_atom(mod) do
    module = module_atoms |> Module.concat()
    pre_require(ast, state, line, module)
  end

  # alias with v1.2 notation
  defp pre(
         {:alias, [line: line, column: _column],
          [{{:., _, [{:__aliases__, _, prefix_atoms}, :{}]}, _, aliases}]} = ast,
         state
       ) do
    aliases_tuples =
      aliases
      |> Enum.map(fn {:__aliases__, _, mods} ->
        {Module.concat(mods), Module.concat(prefix_atoms ++ mods)}
      end)

    pre_alias(ast, state, line, aliases_tuples)
  end

  # alias without options
  defp pre(
         {:alias, [line: line, column: _column], [{:__aliases__, _, module_atoms = [mod | _]}]} =
           ast,
         state
       )
       when is_atom(mod) do
    alias_tuple = {Module.concat([List.last(module_atoms)]), Module.concat(module_atoms)}
    pre_alias(ast, state, line, alias_tuple)
  end

  # alias with `as` option
  defp pre(
         {:alias, [line: line, column: _column],
          [{_, _, module_atoms = [mod | _]}, [as: {:__aliases__, _, alias_atoms = [al | _]}]]} =
           ast,
         state
       )
       when is_atom(mod) and is_atom(al) do
    alias_tuple = {Module.concat(alias_atoms), Module.concat(module_atoms)}
    pre_alias(ast, state, line, alias_tuple)
  end

  # alias erlang module with `as` option
  defp pre(
         {:alias, [line: line, column: _column],
          [mod, [as: {:__aliases__, _, alias_atoms = [al | _]}]]} = ast,
         state
       )
       when is_atom(mod) and is_atom(al) do
    alias_tuple = {Module.concat(alias_atoms), mod}
    pre_alias(ast, state, line, alias_tuple)
  end

  defp pre({atom, [line: line, column: _column], _} = ast, state) when atom in @scope_keywords do
    pre_scope_keyword(ast, state, line)
  end

  defp pre({atom, _block} = ast, state) when atom in @block_keywords do
    pre_block_keyword(ast, state)
  end

  defp pre({:->, meta, [lhs, rhs]}, state) do
    pre_clause({:->, meta, [:_, rhs]}, state, lhs)
  end

  defp pre({:=, meta, [lhs, rhs]}, state) do
    state
    |> add_vars(find_vars(lhs), true)
    |> result({:=, meta, [:_, rhs]})
  end

  defp pre({var_or_call, [line: line, column: column], context} = ast, state)
       when is_atom(var_or_call) and context in [nil, Elixir] do
    if Enum.any?(get_current_vars(state), &(&1.name == var_or_call)) do
      state
      |> add_vars(find_vars(ast), false)
    else
      # pre Elixir 1.4 local call syntax
      # TODO remove on Elixir 2.0
      state
      |> add_call_to_line({nil, var_or_call, 0}, line, column)
      |> add_current_env_to_line(line)
    end
    |> result(ast)
  end

  defp pre({:<-, meta, [lhs, rhs]}, state) do
    state
    |> add_vars(find_vars(lhs), true)
    |> result({:<-, meta, [:_, rhs]})
  end

  # Kernel: defmacro use(module, opts \\ [])
  defp pre({:use, [line: _, column: _], [{param, _, nil} | _]} = ast, state)
       when is_atom(param) do
    state
    |> result(ast)
  end

  defp pre({:use, [line: line, column: column], _} = ast, state) do
    # take first variant as we optimistically assume that the result of expanding `use` will be the same for all variants
    current_module = get_current_module(state)

    current_module_length =
      case current_module do
        Elixir -> 0
        other -> length(Module.split(other))
      end

    current_module_variants = get_current_module_variants(state)

    %{
      requires: requires,
      imports: imports,
      behaviours: behaviours,
      aliases: aliases,
      attributes: attributes,
      mods_funs: mods_funs
    } = Ast.extract_use_info(ast, current_module, state)

    state =
      state
      |> add_aliases(aliases)
      |> add_requires(requires)
      |> add_imports(imports)
      |> add_behaviours(behaviours)
      |> add_attributes(attributes)

    state =
      Enum.reduce(mods_funs, state, fn
        {name, args, type}, acc ->
          acc
          |> add_func_to_index(name, args, {line, column}, type)

        module, acc ->
          submodule_parts = Module.split(module) |> Enum.drop(current_module_length)

          Enum.reduce(current_module_variants, acc, fn variant, acc_1 ->
            module =
              (Module.split(variant) ++ submodule_parts)
              |> Module.concat()

            acc_1
            |> add_module_to_index(module, {line, column})
          end)
      end)

    state
    |> add_current_env_to_line(line)
    |> result(ast)
  end

  defp pre({type, _, fields} = ast, state) when type in [:defstruct, :defexception] do
    fields =
      case fields do
        [fields] -> if Keyword.keyword?(fields), do: fields, else: []
        _ -> []
      end

    state =
      if type == :defexception do
        state
        |> add_behaviour(Exception)
      else
        state
      end

    state
    |> add_struct(type, fields)
    |> result(ast)
  end

  # transform `a |> b(c)` calls into `b(a, c)`
  defp pre({:|>, _, [params_1, {call, [line: line, column: column], params_rest}]}, state) do
    params = [params_1 | params_rest || []]
    pre({call, [line: line, column: column], params}, state)
  end

  # transform external and local func capture into fake call
  defp pre({:&, _, [{:/, _, [fun, arity]}]}, state) when is_integer(arity) do
    fake_params =
      if arity == 0 do
        []
      else
        for _ <- 1..arity, do: nil
      end

    call =
      case fun do
        {func, position, nil} ->
          {func, position, fake_params}

        {{:., _, [{:__aliases__, _, _}, _]} = ast_part, position, []} ->
          {ast_part, position, fake_params}
      end

    pre(call, state)
  end

  defp pre({call, [line: line, column: column], params} = ast, state)
       when is_call(call, params) do
    state =
      if !String.starts_with?(to_string(call), "__atom_elixir_marker_") do
        add_call_to_line(state, {nil, call, length(params)}, line, column)
      else
        state
      end

    state
    |> add_current_env_to_line(line)
    |> result(ast)
  end

  defp pre(
         {{:., _, [{:__aliases__, _, mod_path}, call]}, [line: line, column: col], params} = ast,
         state
       )
       when is_call(call, params) do
    mod = Module.concat(mod_path)

    state
    |> add_call_to_line({mod, call, length(params)}, line, col)
    |> add_current_env_to_line(line)
    |> result(ast)
  end

  # Any other tuple with a line
  defp pre({_, [line: line, column: _column], _} = ast, state) do
    state
    |> add_current_env_to_line(line)
    |> result(ast)
  end

  # No line defined
  defp pre(ast, state) do
    {ast, state}
  end

  defp post({:defmodule, _, [{:__aliases__, _, module}, _]} = ast, state) do
    post_module(ast, state, module)
  end

  defp post({:defprotocol, _, [{:__aliases__, _, module}, _]} = ast, state) do
    post_module(ast, state, module)
  end

  defp post({:defimpl, _, [{:__aliases__, _, protocol}, [for: implementations], _]} = ast, state) do
    case implementations do
      list when is_list(list) ->
        modules =
          list
          |> Enum.map(fn {:__aliases__, _, implementation} ->
            implementation
          end)

        post_module(ast, state, {protocol, modules})

      {:__aliases__, _, implementation} ->
        post_module(ast, state, {protocol, [implementation]})
    end
  end

  defp post({def_name, [line: _line, column: _column], [{name, _, _params}, _]} = ast, state)
       when def_name in @defs and is_atom(name) do
    post_func(ast, state)
  end

  defp post({def_name, _, _} = ast, state) when def_name in @defs do
    {ast, state}
  end

  defp post({atom, _, _} = ast, state) when atom in @scope_keywords do
    post_scope_keyword(ast, state)
  end

  defp post({atom, _block} = ast, state) when atom in @block_keywords do
    post_block_keyword(ast, state)
  end

  defp post({:->, [line: _line, column: _column], [_lhs, _rhs]} = ast, state) do
    post_clause(ast, state)
  end

  # String literal
  defp post({_, [no_call: true, line: line, column: _column], [str]} = ast, state)
       when is_binary(str) do
    post_string_literal(ast, state, line, str)
  end

  # String literal in sigils
  defp post({:<<>>, [line: line, column: _column], [str]} = ast, state) when is_binary(str) do
    post_string_literal(ast, state, line, str)
  end

  defp post(ast, state) do
    {ast, state}
  end

  defp result(state, ast) do
    {ast, state}
  end

  defp find_vars(ast) do
    {_ast, vars} = Macro.prewalk(ast, [], &match_var/2)
    vars
  end

  defp match_var({var, [line: line, column: column], context} = ast, vars)
       when is_atom(var) and context in [nil, Elixir] do
    var_info = %VarInfo{name: var, positions: [{line, column}]}
    {ast, [var_info | vars]}
  end

  defp match_var(ast, vars) do
    {ast, vars}
  end

  defp add_no_call(meta) do
    [{:no_call, true} | meta]
  end
end
