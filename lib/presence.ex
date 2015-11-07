defmodule Presence do
  @moduledoc """
  A generic structure for associating values with dots (version vector pairs).

  They reflect work from ORSWOT (optimized observed-remove set without tombstones).
  """

  @type actor :: term
  @type clock :: pos_integer
  @type dot :: {actor, clock}
  @type value :: term
  @type opts :: Keyword.t

  @type joins :: [value]
  @type parts :: [value]

  @opaque t :: %__MODULE__{
    actor: nil,
    dots: %{dot => value},
    ctx: %{actor => clock},
    cloud: [dot],
    delta: %{
      actor: nil,
      dots: [],
      cloud: []
    },
    servers: %{}
  }

  defstruct actor: nil,
            dots: %{}, # A map of dots (version-vector pairs) to values
            ctx: %{},  # Current counter values for actors used in the dots
            cloud: [],  # A set of dots that we've seen but haven't been merged.
            delta: %{
              actor: nil,
              dots: [],
              cloud: []
            },
            servers: %{}

  @spec new(term) :: t
  def new(node) do
    servers = Enum.into([{node, :up}], %{})
    %Presence{actor: node, actor: node, servers: servers}
  end

  @spec node_down(t, term) :: {t, joins, parts}
  def node_down(%Presence{servers: servers}=set, node) do
    new_set = %Presence{set|servers: Dict.put(servers, node, :down)}
    {new_set, [], node_users(new_set, node)}
  end

  @spec node_up(t, term) :: {t, joins, parts}
  def node_up(%Presence{servers: servers}=set, node) do
    new_set = %Presence{set|servers: Dict.put(servers, node, :up)}
    {new_set, node_users(new_set, node), []}
  end

  @spec join(t, value) :: t
  def join(%Presence{}=set, user) do
    add(set, user)
  end

  @spec part(t, value) :: t
  def part(%Presence{}=set, user) do
    remove(set, user)
  end

  @spec is_online(t, value) :: boolean
  def is_online(%Presence{dots: dots}=set, user) do
    down = down_nodes(set)
    Enum.any?(dots, fn
      {{node, _}, user1} -> user1 === user and node in down
      _ -> false
    end)
  end

  @spec online_users(t) :: [value]
  def online_users(%{dots: dots, servers: servers}) do
    for {{node,_}, user} <- dots, Map.get(servers, node, :up) == :up do
      user
    end |> Enum.uniq
  end

  defp node_users(%{dots: dots}, node) do
    for {{n,_}, user} <- dots, n===node do
      {node, user}
    end |> Enum.uniq
  end

  @spec offline_users(t) :: [value]
  def offline_users(%{dots: dots, servers: servers}) do
    for {{node,_}, user} <- dots, Map.get(servers, node, :up) == :down do
      user
    end |> Enum.uniq
  end

  @spec down_nodes(t) :: [node]
  def down_nodes(%Presence{servers: nodes}) do
    for {node, :down} <- nodes, do: node
  end

  @doc """
  Compact the dots.

  This merges any newly-contiguously-joined deltas. This is usually called
  automatically as needed.
  """
  @spec compact(t) :: t
  def compact(dots), do: do_compact(dots)

  @doc """
  Joins any 2 dots together.

  Automatically compacts any contiguous dots.
  """
  @spec merge(t, t) :: {t, joins, parts}
  def merge(dots1, dots2), do: do_merge(dots1, dots2)

  @doc """
  Adds and associates a value with a new dot for an actor.
  """
  @spec add(t, value) :: t
  def add(%{actor: nil}, _), do: raise ArgumentError, "Actor is required"
  def add(%{actor: actor, dots: dots, ctx: ctx}=t, value) do
    clock = Dict.get(ctx, actor, 0) + 1 # What's the value of our clock?
    %{t |
      dots: Dict.put(dots, {actor, clock}, value), # Add the value to the dot values
      ctx: Dict.put(ctx, actor, clock) # Add the actor/clock to the context
    }
  end

  @doc """
  Removes a value from the set
  """
  @spec remove(t | {t, t}, value | (value -> boolean)) :: t
  def remove(%{dots: dots}=t, pred) when is_function(pred) do
    new_dots = for {dot, v} <- dots, !pred.(v), into: %{}, do: {dot, v}
    %{t|dots: new_dots}
  end
  def remove(_, value) when is_function(value), do: raise ArgumentError, "Illegal dot pattern"
  def remove(dots, value), do: remove(dots, &(&1==value))

  defp do_compact(%{ctx: ctx, cloud: c}=dots) do
    {new_ctx, new_cloud} = compact_reduce(Enum.sort(c), ctx, [])
    %{dots|ctx: new_ctx, cloud: new_cloud}
  end

  defp compact_reduce([], ctx, cloud_acc) do
    {ctx, Enum.reverse(cloud_acc)}
  end
  defp compact_reduce([{actor, clock}=dot|cloud], ctx, cloud_acc) do
    case {ctx[actor], clock} do
      {nil, 1} ->
        # We can merge nil with 1 in the cloud
        compact_reduce(cloud, Dict.put(ctx, actor, clock), cloud_acc)
      {nil, _} ->
        # Can't do anything with this
        compact_reduce(cloud, ctx, [dot|cloud_acc])
      {ctx_clock, _} when ctx_clock + 1 == clock ->
        # Add to context, delete from cloud
        compact_reduce(cloud, Dict.put(ctx, actor, clock), cloud_acc)
      {ctx_clock, _} when ctx_clock >= clock -> # Dominates
        # Delete from cloud by not accumulating.
        compact_reduce(cloud, ctx, cloud_acc)
      {_, _} ->
        # Can't do anything with this.
        compact_reduce(cloud, ctx, [dot|cloud_acc])
    end
  end

  defp dotin(%Presence{ctx: ctx, cloud: cloud}, {actor, clock}=dot) do
    # If this exists in the dot, and is greater than the value *or* is in the cloud
    (ctx[actor]||0) >= clock or Enum.any?(cloud, &(&1==dot))
  end

  defp do_merge(%{dots: d1, ctx: ctx1, cloud: c1}=set1, %{dots: d2, ctx: ctx2, cloud: c2}=set2) do
    # new_dots = do_merge_dots(Enum.sort(d1), Enum.sort(d2), {dots1, dots2}, [])
    {new_dots,j,p} = Enum.sort(extract_dots(d1, set2) ++ extract_dots(d2, set1))
               |> merge_dots(set1, {%{},[],[]})
    new_ctx = Dict.merge(ctx1, ctx2, fn (_, a, b) -> max(a, b) end)
    new_cloud = Enum.uniq(c1 ++ c2)
    {compact(%{set1|dots: new_dots, ctx: new_ctx, cloud: new_cloud}),j,p}
  end

  # Pair each dot with the set opposite it for comparison
  defp extract_dots(dots, set) do
    for pair <- dots, do: {pair, set}
  end

  defp merge_dots([], _, acc), do: acc

  defp merge_dots([{{dot,value}=pair,_}, {pair,_} |rest], set1, {acc,j,p}) do
    merge_dots(rest, set1, {Dict.put(acc, dot, value),j,p})
  end

  # Our dot's values aren't the same. This is an invariant and shouldn't happen. ever.
  defp merge_dots([{{dot,_},_}, {{dot,_},_}|_], _, _acc) do
    raise Presence.InvariantError, "2 dot-pairs with the same dot but different values"
  end

  # Our dots aren't the same.
  defp merge_dots([{{{actor, clock},value}, oppset}|rest], %{actor: me}=set1, {acc,j,p}) do
    # Check to see if this dot is in the opposite CRDT
    new_acc = if dotin(oppset, {actor,clock}) do # It *was* here, we drop it (observed-delete dot-pair)
      new_p = if actor != me, do: [{actor, value}|p], else: p # set1.on_part.(value, actor)
      {acc,j,new_p}
    else # If it wasn't here, we keep it (concurrent update)
      new_j = if actor != me, do: [{actor,value}|j], else: j # set1.on_join.(value, actor)
      acc = Dict.put(acc, {actor,clock}, value)
      {acc,new_j,p}
    end
    merge_dots(rest, set1, new_acc)
  end

end

defmodule Presence.Invariant do
  defexception [:message]
end
