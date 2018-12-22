defmodule StockfixTest do
  use ExUnit.Case
  doctest Stockfix

  test "greets the world" do
    assert Stockfix.hello() == :world
  end
end
