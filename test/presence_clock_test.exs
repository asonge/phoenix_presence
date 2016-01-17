defmodule PresenceClockTest do
  use ExUnit.Case
  alias Presence.Clock

  test "basic dominates" do
    clock1 = %{a: 1, b: 2, c: 3}
    clock2 = %{b: 2, c: 3, d: 1}
    clock3 = %{a: 1, b: 2}
    assert true == Clock.dominates?(clock1, clock3)
    assert false == Clock.dominates?(clock3, clock1)
    assert false == Clock.dominates?(clock1, clock2)
  end

  test "test the set trims..." do
    clock1 = %{a: 1, b: 2, c: 3}
    clock2 = %{b: 2, c: 3, d: 1}
    clock3 = %{a: 1, b: 2}
    assert [clock3, clock2] == Clock.append_clock([clock2, clock3], clock1) |> Enum.sort
    assert [clock1, clock2] == Clock.append_clock([clock1, clock2], clock3) |> Enum.sort
    assert [clock1, clock2] == Clock.append_clock([clock1, clock2], clock1) |> Enum.sort
    assert [clock1, clock2] == Clock.append_clock([clock1, clock2], clock2) |> Enum.sort
    assert [clock3, clock1, clock2] == Clock.append_clock([clock1, clock3], clock2) |> Enum.sort
  end

end
