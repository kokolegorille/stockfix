defmodule Stockfix.TextClient.State do
  @moduledoc false

  defstruct(
    engine: nil,
    fen: nil,
    moves: [],
    bestmove: nil,
    ponder: nil,
    ponder_mode: true
  )
end
