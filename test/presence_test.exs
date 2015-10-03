defmodule PresenceTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  require Logger
  doctest Presence

  alias Presence.Agent, as: Presence

  # New print-callback Presence
  defp newp(node) do
    {:ok, pid} = Presence.start_link(node, &Logger.info("join #{inspect &1} #{inspect &2}"), &Logger.info("part #{inspect &1} #{inspect &2}"))
    pid
  end

  test "That this is set up correctly" do
    a = newp(:a)
    assert [] = Presence.online_users(a)
    assert [] = Presence.offline_users(a)
  end

  test "User added online is online" do
    a = newp(:a)
    assert capture_log(fn -> Presence.join(a, :john) end) =~ ~r"join :john :a"
    assert [:john] = Presence.online_users(a)
    assert capture_log(fn -> Presence.part(a, :john) end) =~ ~r"part :john :a"
    assert [] = Presence.online_users(a)
  end

  test "Users from other servers merge" do
    a = newp(:a)
    b = newp(:b)

    assert capture_log(fn -> Presence.join(a, :alice) end) =~ ~r"join :alice :a"
    assert capture_log(fn -> Presence.join(b, :bob) end) =~ ~r"join :bob :b"

    assert capture_log(fn -> Presence.merge(a, b) end) =~ ~r"join :bob :b"
    assert [:alice, :bob] = Presence.online_users(a) |> Enum.sort

    assert "" = capture_log(fn -> Presence.merge(a, b) end)

    assert capture_log(fn -> Presence.merge(b, a) end) =~ ~r"join :alice :a"
    assert "" = capture_log(fn -> Presence.merge(b, a) end)
    assert capture_log(fn -> Presence.part(a, :alice) end) =~ ~r"part :alice :a"

    assert capture_log(fn -> Presence.merge(b, a) end) =~ ~r"part :alice :a"
    assert [:bob] = Presence.online_users(b) |> Enum.sort
    assert "" = capture_log(fn -> Presence.merge(b, a) end)

    assert capture_log(fn -> Presence.join(b, :carol) end) =~ ~r"join :carol :b"

    assert [:bob, :carol] = Presence.online_users(b) |> Enum.sort
    assert capture_log(fn -> Presence.merge(a, b) end) =~ ~r"join :carol :b"
    assert "" = capture_log(fn -> Presence.merge(a, b) end)

    assert (Presence.online_users(b) |> Enum.sort) == (Presence.online_users(a) |> Enum.sort)

  end

  test "Netsplit" do
    a = newp(:a)
    b = newp(:b)
    capture_log(fn ->
      Presence.join(a, :alice)
      Presence.join(b, :bob)
      Presence.merge(a, b)
    end)

    assert [:alice, :bob] = Presence.online_users(a) |> Enum.sort

    capture_log(fn ->
      Presence.merge(a, b)
      Presence.join(a, :carol)
      Presence.part(a, :alice)
      Presence.join(a, :david)
      Presence.node_down(a, :b)
    end)

    assert [:carol, :david] = Presence.online_users(a) |> Enum.sort

    capture_log(fn ->
      Presence.merge(a, b)
    end)
    assert [:carol, :david] = Presence.online_users(a) |> Enum.sort

    capture_log(fn ->
      Presence.node_up(a, :b)
    end)

    assert [:bob, :carol, :david] = Presence.online_users(a) |> Enum.sort
  end
  
end
