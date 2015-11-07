defmodule PresenceTest do
  use ExUnit.Case
  require Logger
  doctest Presence

  # Partial netsplit multiple joins

  # New print-callback Presence
  defp newp(node) do
    Presence.new(node)
  end

  test "That this is set up correctly" do
    a = newp(:a)
    assert [] = Presence.online_users(a)
    assert [] = Presence.offline_users(a)
  end

  test "User added online is online" do
    a = newp(:a)
    a = Presence.join(a, :john)
    assert [:john] = Presence.online_users(a)
    a = Presence.part(a, :john)
    assert [] = Presence.online_users(a)
  end

  test "Users from other servers merge" do
    a = newp(:a)
    b = newp(:b)

    a = Presence.join(a, :alice)
    b = Presence.join(b, :bob)

    # Merging emits a bob part event
    assert {a,[{_,:bob}],[]} = Presence.merge(a, b)
    assert [:alice,:bob] = Presence.online_users(a) |> Enum.sort

    # Merging twice doesn't dupe events
    assert {^a,[],[]} = Presence.merge(a, b)

    assert {b,[{_,:alice}],[]} = Presence.merge(b, a)
    assert {^b,[],[]} = Presence.merge(b,a)
    a = Presence.part(a, :alice)
    assert {b,[],[{_,:alice}]} = Presence.merge(b, a)

    assert [:bob] = Presence.online_users(b) |> Enum.sort
    assert {^b,[],[]} = Presence.merge(b, a)

    b = Presence.join(b, :carol)

    assert [:bob, :carol] = Presence.online_users(b) |> Enum.sort
    assert {a,[{_,:carol}],[]} = Presence.merge(a, b)
    assert {^a,[],[]} = Presence.merge(a, b)

    assert (Presence.online_users(b) |> Enum.sort) == (Presence.online_users(a) |> Enum.sort)

  end

  test "Netsplit" do
    a = newp(:a)
    b = newp(:b)

    a = Presence.join(a, :alice)
    b = Presence.join(b, :bob)
    {a, [{_, :bob}], _} = Presence.merge(a, b)

    assert [:alice, :bob] = Presence.online_users(a) |> Enum.sort

    a = Presence.join(a, :carol)
    a = Presence.part(a, :alice)
    a = Presence.join(a, :david)
    assert {a,[],[{_,:bob}]} = Presence.node_down(a, :b)

    assert [:carol, :david] = Presence.online_users(a) |> Enum.sort

    assert {a,[],[]} = Presence.merge(a, b)
    assert [:carol, :david] = Presence.online_users(a) |> Enum.sort

    assert {a,[{_,:bob}],[]} = Presence.node_up(a, :b)

    assert [:bob, :carol, :david] = Presence.online_users(a) |> Enum.sort
  end

end
