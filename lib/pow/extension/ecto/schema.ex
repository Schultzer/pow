defmodule Pow.Extension.Ecto.Schema do
  @moduledoc """
  Handles extensions for the user Ecto schema.

  The macro will append fields to the `@pow_fields` module attribute using the
  attributes from `[Pow Extension].Ecto.Schema.attrs/1`, so they can be used in
  the `Pow.Ecto.Schema.pow_user_fields/0` method call.

  After module compilation `[Pow Extension].Ecto.Schema.validate!/2` will run.

  ## Usage

  Configure `lib/my_project/users/user.ex` the following way:

      defmodule MyApp.Users.User do
        use Ecto.Schema
        use Pow.Ecto.Schema
        use Pow.Extension.Ecto.Schema,
          extensions: [PowExtensionOne, PowExtensionTwo]

        schema "users" do
          pow_user_fields()

          timestamps()
        end

        def changeset(user_or_changeset, attrs) do
          user
          |> pow_changeset(attrs)
          |> pow_extension_changeset(attrs)
        end
      end
  """
  alias Ecto.Changeset
  alias Pow.{Config, Extension}

  defmodule SchemaError do
    defexception [:message]
  end

  @doc false
  defmacro __using__(config) do
    quote do
      @pow_extension_config Config.merge(@pow_config, unquote(config))

      Module.eval_quoted(__MODULE__, unquote(__MODULE__).__use_extensions__(@pow_extension_config))

      unquote(__MODULE__).__register_extension_fields__()
      unquote(__MODULE__).__register_extension_assocs__()
      unquote(__MODULE__).__pow_extension_methods__()
      unquote(__MODULE__).__register_after_compile_validation__()
    end
  end

  @doc false
  def __use_extensions__(config) do
    config
    |> schema_modules()
    |> Enum.filter(&Kernel.macro_exported?(&1, :__using__, 1))
    |> Enum.map(fn module ->
      quote do
        use unquote(module), unquote(config)
      end
    end)
  end

  @doc false
  defmacro __register_extension_fields__ do
    quote do
      for attr <- unquote(__MODULE__).attrs(@pow_extension_config) do
        Module.put_attribute(__MODULE__, :pow_fields, attr)
      end
    end
  end

  @doc false
  defmacro __register_extension_assocs__ do
    quote do
      @pow_extension_config
      |> unquote(__MODULE__).assocs()
      |> Enum.map(fn
        {:belongs_to, name, :users} -> {:belongs_to, name, __MODULE__}
        {:has_many, name, :users, opts} -> {:has_many, name, __MODULE__, opts}
      end)
      |> Enum.each(&Module.put_attribute(__MODULE__, :pow_assocs, &1))
    end
  end

  @doc false
  defmacro __pow_extension_methods__ do
    quote do
      @spec pow_extension_changeset(Changeset.t(), map()) :: Changeset.t()
      def pow_extension_changeset(changeset, attrs) do
        unquote(__MODULE__).changeset(changeset, attrs, @pow_extension_config)
      end
    end
  end

  @doc false
  defmacro __register_after_compile_validation__ do
    quote do
      def validate_after_compilation!(env, _bytecode) do
        unquote(__MODULE__).validate!(@pow_extension_config, __MODULE__)
      end

      @after_compile {__MODULE__, :validate_after_compilation!}
    end
  end

  @doc """
  Merge all extension attributes together to one list.

  The extension ecto schema modules is discovered through the `:extensions` key
  in the configuration, and the attribute list will be in the same order as the
  extensions list.
  """
  @spec attrs(Config.t()) :: [tuple]
  def attrs(config) do
    config
    |> schema_modules()
    |> Enum.reduce([], fn extension, attrs ->
      extension_attrs = extension.attrs(config)

      Enum.concat(attrs, extension_attrs)
    end)
  end


  @doc """
  Merge all extension associations together to one list.

  The extension ecto schema modules is discovered through the `:extensions` key
  in the configuration, and the attribute list will be in the same order as the
  extensions list.
  """
  @spec assocs(Config.t()) :: [tuple]
  def assocs(config) do
    config
    |> schema_modules()
    |> Enum.reduce([], fn extension, assocs ->
      extension_assocs = extension.assocs(config)

      Enum.concat(assocs, extension_assocs)
    end)
  end

  @doc """
  Merge all extension indexes together to one list.

  The extension ecto schema modules is discovered through the `:extensions` key
  in the configuration, and the index list will be in the same order as the
  extensions list.
  """
  @spec indexes(Config.t()) :: [tuple]
  def indexes(config) do
    config
    |> schema_modules()
    |> Enum.reduce([], fn extension, indexes ->
      extension_indexes = extension.indexes(config)

      Enum.concat(indexes, extension_indexes)
    end)
  end

  @doc """
  This will run `changeset/3` on all extension ecto schema modules.

  The extension ecto schema modules is discovered through the `:extensions` key
  in the configuration, and the changesets will be piped in the same order
  as the extensions list.
  """
  @spec changeset(Changeset.t(), map(), Config.t()) :: Changeset.t()
  def changeset(changeset, attrs, config) do
    config
    |> schema_modules()
    |> Enum.reduce(changeset, fn extension, changeset ->
      extension.changeset(changeset, attrs, config)
    end)
  end

  @doc """
  This will run `validate!/2` on all extension ecto schema modules.

  It's used to ensure certain fields are available, e.g. an `:email` field. The
  method should either raise an exception, or return `:ok`. Compilation will
  fail when the exception is raised.
  """
  @spec validate!(Config.t(), atom()) :: :ok | no_return
  def validate!(config, module) do
    config
    |> schema_modules()
    |> Enum.each(& &1.validate!(config, module))

    :ok
  end

  defp schema_modules(config) do
    Extension.Config.discover_modules(config, ["Ecto", "Schema"])
  end

  @doc """
  Validates that the ecto schema has the specified field.

  If the field doesn't exist, it'll raise an exception.
  """
  @spec require_schema_field!(atom(), atom(), atom()) :: :ok | no_return
  def require_schema_field!(module, field, extension) do
    fields = module.__schema__(:fields)

    fields
    |> Enum.member?(field)
    |> case do
      true  -> :ok
      false -> raise_missing_field_error(module, field, extension)
    end
  end

  defp raise_missing_field_error(module, field, extension) do
    raise SchemaError, message: "A `#{inspect field}` schema field should be defined in #{inspect module} to use #{inspect extension}"
  end
end
