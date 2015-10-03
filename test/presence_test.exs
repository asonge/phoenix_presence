defmodule PresenceTest do
  use ExUnit.Case, async: false
  require Logger
  doctest Presence

  # New print-callback Presence
  defp newp(node) do
    Presence.new(node, &Logger.info("join\t#{inspect &1}\t#{inspect &2}"),
                       &Logger.info("part\t#{inspect &1}\t#{inspect &2}"))
  end

  test "That this is set up correctly" do
    a = newp(:a)
    assert [] = Presence.online_users(a)
    assert [] = Presence.offline_users(a)
  end

  test "User added online is online" do
    assert [:john] = newp(:a) |> Presence.join(:john) |> Presence.online_users
    assert [] = newp(:a) |> Presence.join(:john) |> Presence.part(:john) |> Presence.online_users
  end

  test "Users from other servers merge" do
    a = newp(:a) |> Presence.join(:alice)
    b = newp(:b) |> Presence.join(:bob)
    assert [:alice, :bob] = Presence.merge(a, b) |> Presence.online_users |> Enum.sort
    # Commutivity
    assert [:alice, :bob] = Presence.merge(b, a) |> Presence.online_users |> Enum.sort
    a1 = a |> Presence.join(:carol) |> Presence.part(:alice)
    assert [:bob, :carol] = Presence.merge(a1, b) |> Presence.online_users |> Enum.sort
  end

  test "Netsplit" do
    a = newp(:a) |> Presence.join(:alice)
    b = newp(:b) |> Presence.join(:bob)
    assert [:alice, :bob] = Presence.merge(a, b) |> Presence.online_users |> Enum.sort
    assert [:alice, :bob] = Presence.merge(b, a) |> Presence.online_users |> Enum.sort

    a1 = a |> Presence.merge(b) |> Presence.join(:carol) |> Presence.part(:alice) |> Presence.join(:david) |> Presence.node_down(:b)

    assert [:carol, :david] = a1 |> Presence.online_users |> Enum.sort
    assert [:carol, :david] = Presence.merge(a1, b) |> Presence.online_users |> Enum.sort

    assert [:bob, :carol, :david] = a1 |> Presence.node_up(:b) |> Presence.online_users |> Enum.sort
  end

  test "Long tail parts" do
    a = newp(:a) |> Presence.join(:alice)
    b = newp(:b) |> Presence.join(:bob) |> Presence.join(:carol) |> Presence.join(:derrick) |> Presence.join(:erica)
                 |> Presence.part(:carol) |> Presence.part(:derrick) |> Presence.part(:erica)
    assert [:alice, :bob] = Presence.merge(a, b) |> Presence.online_users |> Enum.sort
    assert [:alice, :bob] = Presence.merge(b, a) |> Presence.online_users |> Enum.sort
  end

  test "On both sides of the netsplit" do
    a = newp(:a) |> Presence.join(:alice) |> Presence.join(:bob)
    b = newp(:b) |> Presence.join(:bob)
    assert [:alice, :bob] = Presence.merge(a, b) |> Presence.online_users |> Enum.sort
    assert [:alice, :bob] = Presence.merge(b, a) |> Presence.online_users |> Enum.sort

    a1 = a |> Presence.merge(b) |> Presence.join(:carol) |> Presence.part(:alice) |> Presence.join(:david) |> Presence.node_down(:b)

    assert [:bob, :carol, :david] = a1 |> Presence.online_users |> Enum.sort
  end

end
