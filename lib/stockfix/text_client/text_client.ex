defmodule Stockfix.TextClient do
  @moduledoc """
  The text client
  """

  require Logger
  alias Stockfix.Workers.Engine
  alias Stockfix.TextClient.{State, Summary, Player}

  @default_fen "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

  def start(options \\ []) do
    fen = Keyword.get(options, :fen, @default_fen)
    ponder_mode = Keyword.get(options, :ponder_mode, true)

    case Chessfold.string_to_position(fen) do
      %Chessfold.Position{} = _position ->
        {:ok, engine} = Engine.start_link()
        Summary.display(fen)
        loop(%State{engine: engine, fen: fen, ponder_mode: ponder_mode})
      {:error, reason} ->
        {:error, reason}
    end
  end

  def loop(%State{} = client) do
    case Player.accept_move(client) do
      %State{} = client -> loop(client)
      {:error, reason} -> {:error, reason}
    end
  end

  def stop(%State{engine: engine}) do
    Engine.quit(engine)
    :ok
  end
end
