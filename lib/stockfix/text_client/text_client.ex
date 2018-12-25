defmodule Stockfix.TextClient do
  @moduledoc """
  The text client
  """

  require Logger
  alias Stockfix.Workers.Engine
  alias __MODULE__

  @default_fen "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
  @default_options [movetime: 20_000]
  @default_ponder_mode true

  defstruct(
    engine: nil,
    fen: nil,
    moves: [],
    bestmove: nil,
    ponder: nil,
    ponder_mode: @default_ponder_mode
  )

  def start(options \\ []) do
    fen = Keyword.get(options, :fen, @default_fen)
    ponder_mode = Keyword.get(options, :ponder_mode, @default_ponder_mode)

    case Chessfold.string_to_position(fen) do
      %Chessfold.Position{} = _position ->
        {:ok, engine} = Engine.start_link()
        display_fen(fen)
        %TextClient{engine: engine, fen: fen, ponder_mode: ponder_mode}
      {:error, reason} ->
        {:error, reason}
    end
  end

  def play(
    %TextClient{
      engine: engine, fen: fen, moves: moves, ponder: ponder, ponder_mode: ponder_mode
    } = client,
    move,
    options \\ @default_options
  ) do
    position = Chessfold.string_to_position(fen)
    case Chessfold.play(position, move) do
      {:ok, %Chessfold.Position{} = position} ->
        if ponder_mode do
          if ponder == move do
            Engine.cast(engine, "ponderhit")
          else
            Engine.cast(engine, "stop")
          end
        end

        fen = Chessfold.position_to_string(position)
        Engine.position(engine, fen, to_uci_move(move))

        # This blocks until the engine has finished!
        output = Engine.go(engine, options)

        regex = ~r/bestmove (?<bestmove>.*) ponder (?<ponder>.*)/
        {_datetime, result_line} = List.first(output)

        case Regex.named_captures(regex, result_line) do
          %{"bestmove" => bestmove, "ponder" => ponder} ->
            Logger.debug fn -> "bestmove : #{bestmove} ponder : #{ponder}" end

            {:ok, position} = Chessfold.play(position, from_uci_move(bestmove))
            new_fen = Chessfold.position_to_string(position)
            display_fen(new_fen)

            if ponder_mode do
              # start ponder mode
              Engine.cast(engine, "go ponder #{ponder}")
            end

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
    |> Enum.map(fn row ->
      row
      |> Enum.map(&piece_to_unicode(&1))
      |> Enum.join(" ")
    end)
    |> Enum.join("\n")
    |> IO.puts()
  end

  defp to_uci_move(move) do
    regex = ~r/(?<move>.*)=(?<promotion>.+)/
    case Regex.named_captures(regex, move) do
      %{"move" => mv, "promotion" => promotion} ->
        mv <> String.downcase(promotion)
      _ ->
        move
    end
  end

  defp from_uci_move(move) do
    case String.length(move) do
      4 -> move
      5 ->
        # The move is a promotion!
        start_move = String.slice(move, 0, 4)
        promotion_piece = move
        |> String.at(4)
        |> String.upcase()
        "#{start_move}=#{promotion_piece}"
      _ -> nil
    end
  end

  defp piece_to_unicode(piece) do
    # https://fr.wikipedia.org/wiki/Symboles_d%27%C3%A9checs_en_Unicode
    case piece do
      "K" -> "\u2654"
      "Q" -> "\u2655"
      "R" -> "\u2656"
      "B" -> "\u2657"
      "N" -> "\u2658"
      "P" -> "\u2659"
      "k" -> "\u265A"
      "q" -> "\u265B"
      "r" -> "\u265C"
      "b" -> "\u265D"
      "n" -> "\u265E"
      "p" -> "\u265F"
      _ -> piece
    end
  end
end
