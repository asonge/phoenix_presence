defmodule Util do

  def set_diff(set1, set2) do
    diff(Enum.sort(set1), Enum.sort(set2), [], [])
  end

  defp diff([], [], acc1, acc2), do: {acc1, acc2}
  defp diff([a|r1], [b|r2], acc1, acc2)    when a == b, do: diff(r1, r2, acc1, acc2)
  defp diff([a|r1], [b|_]=set2, acc1, acc2) when a < b, do: diff(r1, set2, [a|acc1], acc2)
  defp diff([a|_]=set1, [b|r2], acc1, acc2) when a > b, do: diff(set1, r2, acc1, [b|acc2])
  defp diff([], set2, acc1, acc2), do: {acc1, acc2 ++ set2}
  defp diff(set1, [], acc1, acc2), do: {acc1 ++ set1, acc2}

end
