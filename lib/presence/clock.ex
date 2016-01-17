defmodule Presence.Clock do

  def append_clock(clockset, clock) do
    big_clock = combine_clocks(clockset)
    cond do
      dominates?(clock, big_clock) -> [clock]
      dominates?(big_clock, clock) -> clockset
      true -> filter_clocks(clockset, clock)
    end
  end

  defp filter_clocks(clockset, clock) do
    # The acc in the reduce is a tuple of the new clockset, and the current status
    clockset
    |> Enum.reduce({[], false}, fn clock2, {set, insert} ->
      if dominates?(clock, clock2) do
        {set, true}
      else
        {[clock2|set], insert || !dominates?(clock2, clock)}
      end
    end)
    |> case do
      {new_clockset, true} -> [clock|new_clockset]
      {new_clockset, false} -> new_clockset
    end
  end

  defp combine_clocks(clockset) do
    Enum.reduce(clockset, %{}, &Map.merge(&1, &2, fn _,a,b -> max(a,b) end))
  end

  # Really fast short-circuit that is just too easy to pass up
  def dominates?(a, b) when map_size(a) < map_size(b), do: false
  def dominates?(a, b) do
    # acc is the map which we will reduce and the status of whether we still dominate
    Enum.reduce(a, {b, true}, &dominates_dot/2) |> does_dominate
  end

  # A simple way of destructuring the return from the reduce...
  # NOTE: assert that b has no leftover data that will cause it to dominate
  defp does_dominate({_, false}), do: false
  defp does_dominate({map, true}), do: map_size(map) == 0

  # How we actually know that we dominate for all clocks in a over those clocks in b
  defp dominates_dot(_, {_, false}), do: false
  defp dominates_dot({actor_a, clock_a}, {b, true}) do
    case Map.pop(b, actor_a, 0) do
      {n, _} when n > clock_a -> {nil, false}
      {_, b2} -> {b2, true}
    end
  end

end
