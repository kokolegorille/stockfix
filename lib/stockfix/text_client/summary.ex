defmodule Stockfix.TextClient.Summary do
  @moduledoc false

  def display(fen) do
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
