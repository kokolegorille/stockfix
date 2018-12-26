defmodule Stockfix.TextClient.Player do
  @moduledoc false
  require Logger

  alias Stockfix.TextClient.{State, Summary}
  alias Stockfix.Workers.Engine

  @move_regex ~r/([a-h][1-8]){2}=?[QRBN]?/
  @default_options [movetime: 20_000]

  def accept_move(%State{} = game) do
    IO.gets("Your move: ")
    |> check_input(game)
  end

  defp check_input({:error, reason}, _) do
    IO.puts("Game ended #{reason}")
    exit(:normal)
  end

  defp check_input(:eof, _) do
    IO.puts("Looks like You gave up...")
    exit(:normal)
  end

  defp check_input(
    input,
    %State{engine: engine, fen: fen, moves: moves, ponder: ponder, ponder_mode: ponder_mode} = game
  ) do
    position = Chessfold.string_to_position(fen)

    cond do
      input =~ @move_regex ->
        move = String.trim(input)

        case Chessfold.play(position, move) do
          {:ok, %Chessfold.Position{} = after_move_position} ->
            if ponder_mode do
              if ponder == move,
                do: Engine.cast(engine, "ponderhit"),
                else: Engine.cast(engine, "stop")
              :readyok = Engine.is_ready(engine)
            end

            after_move_fen = Chessfold.position_to_string(after_move_position)
            Engine.position(engine, after_move_fen, to_uci_move(move))

            accept_computer_move(%{game | fen: after_move_fen, moves: [move | moves]})
        end
      true ->
        IO.puts "Please enter a valid move"
        accept_move(game)
    end
  end

  defp accept_computer_move(
    %State{engine: engine, fen: fen, moves: moves, ponder_mode: ponder_mode} = game,
    options \\ @default_options
  ) do
    # This blocks until the engine has finished!
    output = Engine.go(engine, options)

    regex = ~r/bestmove (?<bestmove>.*) ponder (?<ponder>.*)/
    {_datetime, result_line} = List.first(output)

    case Regex.named_captures(regex, result_line) do
      %{"bestmove" => bestmove, "ponder" => ponder} ->
        Logger.debug fn -> "bestmove : #{bestmove} ponder : #{ponder}" end

        position = Chessfold.string_to_position(fen)

        case Chessfold.play(position, from_uci_move(bestmove)) do
          {:ok, after_computer_move_position} ->
            after_computer_move_fen = Chessfold.position_to_string(after_computer_move_position)
            Summary.display(after_computer_move_fen)

            if ponder_mode do
              # start ponder mode
              Engine.cast(engine, "go ponder #{ponder}")
            end

            # Store moves (in reverse order)
            %State{game |
              fen: after_computer_move_fen,
              moves: [bestmove | moves],
              bestmove: bestmove,
              ponder: ponder
            }
          {:error, reason} ->
            Logger.debug fn -> "#{inspect position} #{bestmove}" end
            {:error, reason}
        end
      nil ->
        {:error, "cannot find best move : #{inspect output}"}
    end
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
end
