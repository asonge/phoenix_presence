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

  @opaque t :: %__MODULE__{
    actor: nil,
    dots: %{dot => value},
    ctx: %{actor => clock},
    cloud: [dot],
    servers: %{},
    on_join: nil,
    on_part: nil
  }

  defstruct actor: nil,
            dots: %{}, # A map of dots (version-vector pairs) to values
            ctx: %{},  # Current counter values for actors used in the dots
            cloud: [],  # A set of dots that we've seen but haven't been merged.
            servers: %{},
            on_join: nil,
            on_part: nil


  def new(node, on_join, on_part) do
    servers = Enum.into([{node, :up}], %{})
    %Presence{actor: node, on_part: on_part, on_join: on_join, actor: node, servers: servers}
  end

  def node_down(%Presence{servers: servers}=set, node) do
    ret = %Presence{set|servers: Dict.put(servers, node, :down)}
    offline_users(ret, fn
      user, n1 when n1 == node -> set.on_part.(user, node)
      _, _ -> nil
    end)
    ret
  end

  def node_up(%Presence{servers: servers}=set, node) do
    ret = %Presence{set|servers: Dict.put(servers, node, :up)}
    online_users(ret, fn
      user, n1 when n1 == node -> set.on_part.(user, node)
      _, _ -> nil
    end)
    ret
  end

  def join(%Presence{actor: actor}=set, user) do
    set.on_join.(user, actor)
    add(set, user)
  end

  def part(%Presence{actor: actor}=set, user) do
    set.on_part.(user, actor)
    remove(set, user)
  end

  def is_online(%Presence{dots: dots}=set, user) do
    down = down_nodes(set)
    dots |> Enum.any?(fn {{node, _}, user1} -> user1 === user and node in down end)
  end

  def online_users(set, cb \\ nil) do
    for {{node,_}, user} <- set.dots, Map.get(set.servers, node, :up) == :up do
      case cb do
        nil -> user
        cb when is_function(cb) -> cb.(user, node)
      end
    end |> Enum.uniq
  end

  def offline_users(set, cb \\ nil) do
    for {{node,_}, user} <- set.dots, Map.get(set.servers, node, :up) == :down do
      case cb do
        nil -> user
        cb when is_function(cb) -> cb.(user, node)
      end
    end |> Enum.uniq
  end

  def down_nodes(set) do
    for {node, :down} <- down_nodes(set), do: node
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
  @spec merge(t, t) :: t
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
  @spec add({t, t}, value) :: {t, t}

  @doc """
  Removes a value from the set
  """
  @spec remove(t | {t, t}, value | (value -> boolean)) :: t | {t, t}
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

  defp do_merge(%{dots: d1, ctx: ctx1, cloud: c1}=dots1, %{dots: d2, ctx: ctx2, cloud: c2}=dots2) do
    new_dots = do_merge_dots(Enum.sort(d1), Enum.sort(d2), {dots1, dots2}, [])
    new_ctx = Dict.merge(ctx1, ctx2, fn (_, a, b) -> max(a, b) end)
    new_cloud = Enum.uniq(c1 ++ c2)
    compact(%{dots1|dots: new_dots, ctx: new_ctx, cloud: new_cloud})
  end

  # This function requires the use of ORDERED lists.
  # If we run out of d2, also takes care of case when we run out of both same time.
  defp do_merge_dots(d1, [], {set1, set2}, acc) do
    # Remove when the other knows about our dots in context/cloud, but isn't in
    # their dot values list (they observed a remove)
    # Before we run, we need to notify:
    my_actor = set1.actor
    new_dots = Enum.reduce(d1, [], fn ({{node,_}=dot, value}=dotvalue, acc) ->
      if(dotin(set2, dot)) do
        if node != my_actor, do: set1.on_part.(value, node)
        acc
      else
        if node != my_actor, do: set1.on_join.(value, node)
        [dotvalue|acc]
      end
    end)
    Enum.reverse(acc, new_dots) |> Enum.into %{}
  end
  # If we run out of d1
  defp do_merge_dots([], d2, {set1, _}, acc) do
    # Add dot when it is only at the other side. This happens when they've got
    # values that we do not.
    my_actor = set1.actor
    new_dots = Enum.reduce(d2, [], fn ({{node,_}=dot, value}=dotvalue, acc) ->
      if(dotin(set1, dot)) do
        if node != my_actor, do: set1.on_part.(value, node)
        acc
      else
        if node != my_actor, do: set1.on_join.(value, node)
        [dotvalue|acc]
      end
    end)
    Enum.reverse(acc, new_dots) |> Enum.into %{}
  end
  # If we both got the same dot, just add it into the accumulator and advance both
  defp do_merge_dots([dot1|d1], [dot2|d2], sets, acc) when dot1 == dot2 do
    do_merge_dots(d1, d2, sets, [dot1|acc])
  end
  defp do_merge_dots([{clock1,_}=dot1|d1], [{clock2,_}|_]=d2, {set1, set2}=sets, acc) when clock1 < clock2 do
    acc = do_merge_dot(set2, dot1, set1.actor, acc)
    do_merge_dots(d1, d2, sets, acc)
  end
  defp do_merge_dots([{clock1,_}|_]=d1, [{clock2,_}=dot2|d2], {set1, _}=sets, acc) when clock2 < clock1 do
    acc = do_merge_dot(set1, dot2, set1.actor, acc)
    do_merge_dots(d1, d2, sets, acc)
  end

  # Remove if we know about the dot and they don't have it in their dots
  # Otherwise keep our dot
  defp do_merge_dot(dots, {{node, _}=dot, value}, actor, acc) do
    if dotin(dots, dot) do
      if actor != node, do: dots.on_part.(value, node)
      acc
    else
      if actor != node, do: dots.on_join.(value, node)
      [{dot, value}|acc]
    end
  end

end

defmodule Presence.Agent do

  def start_link(node, on_join, on_part) do
    servers = Enum.into([{node, :up}], %{})
    Agent.start_link(fn ->
      %Presence{actor: node, on_part: on_part, on_join: on_join, actor: node, servers: servers}
    end)
  end

  def node_down(pid, node), do: Agent.update(pid, &Presence.node_down(&1, node))
  def node_up(pid, node), do: Agent.update(pid, &Presence.node_up(&1, node))

  def join(pid, user), do: Agent.update(pid, &Presence.join(&1, user))
  def part(pid, user), do: Agent.update(pid, &Presence.part(&1, user))

  def is_online(pid, user), do: Agent.update(pid, user)

  def online_users(pid), do: Agent.get(pid, &Presence.online_users/1)
  def offline_users(pid), do: Agent.get(pid, &Presence.offline_users/1)

  def merge(pid, set) when is_pid(set), do: merge(pid, Agent.get(set, &(&1)))
  def merge(pid, %Presence{}=set), do: Agent.update(pid, &Presence.merge(&1, set))

end
