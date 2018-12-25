defmodule Stockfix.TextClient do
  @moduledoc """
  The text client
  """

  require Logger
  alias Stockfix.Workers.Engine
  alias __MODULE__

  @default_fen "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
  @default_options [movetime: 30_000]

  defstruct(
    engine: nil,
    fen: nil,
    moves: [],
    bestmove: nil,
    ponder: nil
  )

  def start(fen \\ @default_fen) do
    case Chessfold.string_to_position(fen) do
      %Chessfold.Position{} = _position ->
        {:ok, engine} = Engine.start_link()
        display_fen(fen)
        %TextClient{engine: engine, fen: fen}
      {:error, reason} ->
        {:error, reason}
    end
  end

  def play(
    %TextClient{engine: engine, fen: fen, moves: moves} = client,
    move,
    options \\ @default_options
  ) do
    position = Chessfold.string_to_position(fen)
    case Chessfold.play(position, move) do
      {:ok, %Chessfold.Position{} = position} ->
        # Check if ponder = move
        # If so, ponderhit
        # if not, send a stop, if ponder is on!

        fen = Chessfold.position_to_string(position)
        Engine.position(engine, fen, to_uci_move(move))

        output = Engine.go(engine, options)
        regex = ~r/bestmove (?<bestmove>.*) ponder (?<ponder>.*)/
        {_datetime, result_line} = List.first(output)

        case Regex.named_captures(regex, result_line) do
          %{"bestmove" => bestmove, "ponder" => ponder} ->
            Logger.debug fn -> "bestmove : #{bestmove} ponder : #{ponder}" end

            # start ponder if activated

            {:ok, position} = Chessfold.play(position, from_uci_move(bestmove))
            new_fen = Chessfold.position_to_string(position)
            display_fen(new_fen)

            # Store moves (in reverse order)
            %{client |
              fen: new_fen,
              moves: [bestmove, move | moves],
              bestmove: bestmove,
              ponder: ponder
            }
          nil ->
            {:error, "cannot find best move : #{inspect output}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def stop(%TextClient{engine: engine}) do
    Engine.quit(engine)
    :ok
  end

  defp display_fen(fen) do
    fen
    |> Chessfold.string_to_position()
    |> Chessfold.print_position()
    |> IO.inspect()
  end

  def to_uci_move(move) do
    regex = ~r/(?<move>.*)=(?<promotion>.+)/
    case Regex.named_captures(regex, move) do
      %{"move" => mv, "promotion" => promotion} ->
        mv <> String.downcase(promotion)
      _ ->
        move
    end
  end

  def from_uci_move(move) do
    case String.length(move) do
      4 -> move
      5 -> "#{String.slice(move, 0, 4)}=#{move |> String.at(4) |> String.upcase()}"
      _ -> nil
    end
  end
end
