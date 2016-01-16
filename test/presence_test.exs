defmodule PresenceTest do
  use ExUnit.Case
  require Logger
  doctest Presence

  # Partial netsplit multiple joins

  # New print-callback Presence
  defp newp(node) do
    Presence.new({node, 1})
  end

  defp new_conn() do
    make_ref()
  end

  test "That this is set up correctly" do
    a = newp(:a)
    assert [] = Presence.online_users(a)
    assert [] = Presence.offline_users(a)
  end

  test "User added online is online" do
    a = newp(:a)
    john = new_conn()
    a = Presence.join(a, john, "lobby", :john)
    assert [:john] = Presence.online_users(a)
    a = Presence.part(a, john, "lobby")
    assert [] = Presence.online_users(a)
  end

  test "Users from other servers merge" do
    a = newp(:a)
    b = newp(:b)

    alice = new_conn
    bob = new_conn
    carol = new_conn

    a = Presence.join(a, alice, "lobby", :alice)
    b = Presence.join(b, bob, "lobby", :bob)

    # Merging emits a bob join event
    assert {a,[{_,:bob}],[]} = Presence.merge(a, b)
    assert [:alice,:bob] = Presence.online_users(a) |> Enum.sort

    # Merging twice doesn't dupe events
    assert {^a,[],[]} = Presence.merge(a, b)

    assert {b,[{_,:alice}],[]} = Presence.merge(b, a)
    assert {^b,[],[]} = Presence.merge(b, a)
    a = Presence.part(a, alice, "lobby")
    assert {b,[],[{_,:alice}]} = Presence.merge(b, a)

    assert [:bob] = Presence.online_users(b) |> Enum.sort
    assert {^b,[],[]} = Presence.merge(b, a)

    b = Presence.join(b, carol, "lobby", :carol)

    assert [:bob, :carol] = Presence.online_users(b) |> Enum.sort
    assert {a,[{_,:carol}],[]} = Presence.merge(a, b)
    assert {^a,[],[]} = Presence.merge(a, b)

    assert (Presence.online_users(b) |> Enum.sort) == (Presence.online_users(a) |> Enum.sort)

  end

  test "Netsplit" do
    a = newp(:a)
    b = newp(:b)

    alice = new_conn
    bob = new_conn
    carol = new_conn
    david = new_conn

    a = Presence.join(a, alice, "lobby", :alice)
    b = Presence.join(b, bob, "lobby", :bob)
    {a, [{_, :bob}], _} = Presence.merge(a, b)

    assert [:alice, :bob] = Presence.online_users(a) |> Enum.sort

    a = Presence.join(a, carol, "lobby", :carol)
    a = Presence.part(a, alice, "lobby")
    a = Presence.join(a, david, "lobby", :david)
    assert {a,[],[{_,:bob}]} = Presence.node_down(a, {:b,1})

    assert [:carol, :david] = Presence.online_users(a) |> Enum.sort

    assert {a,[],[]} = Presence.merge(a, b)
    assert [:carol, :david] = Presence.online_users(a) |> Enum.sort

    assert {a,[{_,:bob}],[]} = Presence.node_up(a, {:b,1})

    assert [:bob, :carol, :david] = Presence.online_users(a) |> Enum.sort
  end

end
