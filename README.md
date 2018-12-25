# Stockfix

Universal Chess Interface client for Stockfish engine.
It uses port to communicate.

The engine is os dependant, it is possible to download for multiple platforms...

https://stockfishchess.org/download/

Put the file inside priv, and set the default name inside Engine Worker.

It depends on chessfold for managing chess logic.

It is based on https://github.com/twilio/chessms
An Erlang client for Chess via SMS.

## UCI client for Stockfish

The engine is ...

filename = "stockfish-10-64"
exec_name = "#{:code.priv_dir(:stockfix)}/#{filename}"

## Sample UCI dialog

https://chess.stackexchange.com/questions/14216/im-confused-by-uci-pondering-and-time-control

```
GUI -> engine1: position startpos
GUI -> engine1: go wtime 100000 winc 1000 btime 100000 binc 1000
engine1 -> GUI: bestmove e2e4 ponder e7e6
GUI -> engine1: position startpos moves e2e4 e7e6
GUI -> engine1: go ponder wtime 98123 winc 1000 btime 100000 binc 1000
[user or other engine plays the expected e7e6 move]
GUI -> engine1: ponderhit
[engine keeps thinking]
engine1 -> GUI: bestmove d2d4 ponder d7d5
```

http://www.open-chess.org/viewtopic.php?f=5&t=2146

**Ponderhit example:**

```
gui -> engine: position p1 [initial position]
gui -> engine: go wtime xxx btime yyy [engine starts searching]
... time passes
gui <- engine: bestmove a2a3 ponder a7a6 [engine stops]
gui -> engine: position p1 moves a2a3 a7a6 [position after ponder move]
gui -> engine: go ponder wtime xxx btime yyy [engine starts searching]
... time passes (engine does not stop searching until 'stop' or 'ponderhit' is received)
gui -> engine: ponderhit [engine may or may not continue searching depending on time management]
... time passes (or not, engine is free to reply instantly)
gui <- engine: bestmove a3a4 ponder a6a5
```

**Pondermiss example:**

```
gui -> engine: position p1
gui -> engine: go wtime xxx btime yyy [engine starts searching]
... time passes
gui <- engine: bestmove a2a3 ponder a7a6 [engine stops]
gui -> engine: position p1 moves a2a3 a7a6
gui -> engine: go ponder wtime xxx btime yyy [engine starts searching]
... time passes (engine does not stop until 'stop' or 'ponderhit' is received)
gui -> engine: stop [engine stops searching]
gui <- engine: bestmove m1 ponder m2 [this is discarded by gui -]
gui -> engine: position p1 moves a2a3 b7b6... [- because engine2 played a different move]
gui -> engine: go...
```

## Usage

```elixir
iex(1)> client = Stockfix.TextClient.start      
[
  ["r", "n", "b", "q", "k", "b", "n", "r"],
  ["p", "p", "p", "p", "p", "p", "p", "p"],
  [".", ".", ".", ".", ".", ".", ".", "."],
  [".", ".", ".", ".", ".", ".", ".", "."],
  [".", ".", ".", ".", ".", ".", ".", "."],
  [".", ".", ".", ".", ".", ".", ".", "."],
  ["P", "P", "P", "P", "P", "P", "P", "P"],
  ["R", "N", "B", "Q", "K", "B", "N", "R"]
]
%Stockfix.TextClient{
  bestmove: nil,
  engine: #PID<0.158.0>,
  fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
  moves: [],
  ponder: nil
}
iex(2)> client = Stockfix.TextClient.play client, "e2e4"
# lots of lines
04:05:21.115 [debug] 2018-12-25 03:05:21.115526Z "info depth 26 currmove e7e6 currmovenumber 1"
 
04:05:23.491 [debug] 2018-12-25 03:05:23.491835Z "info depth 27 seldepth 36 multipv 1 score cp 25 lowerbound nodes 39834577 nps 1383241 hashfull 999 tbhits 0 time 28798 pv e7e6"
 
04:05:23.491 [debug] 2018-12-25 03:05:23.491929Z "info depth 25 currmove e7e6 currmovenumber 1"
 
04:05:24.694 [debug] 2018-12-25 03:05:24.694743Z "info depth 27 seldepth 36 multipv 1 score cp 25 nodes 41505247 nps 1383462 hashfull 999 tbhits 0 time 30001 pv e7e6"
 
04:05:24.695 [debug] bestmove : e7e6 ponder : d2d4
[
  ["r", "n", "b", "q", "k", "b", "n", "r"],
  ["p", "p", "p", "p", ".", "p", "p", "p"],
  [".", ".", ".", ".", "p", ".", ".", "."],
  [".", ".", ".", ".", ".", ".", ".", "."],
  [".", ".", ".", ".", "P", ".", ".", "."],
  [".", ".", ".", ".", ".", ".", ".", "."],
  ["P", "P", "P", "P", ".", "P", "P", "P"],
  ["R", "N", "B", "Q", "K", "B", "N", "R"]
]
%Stockfix.TextClient{
  bestmove: "e7e6",
  engine: #PID<0.158.0>,
  fen: "rnbqkbnr/pppp1ppp/4p3/8/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2",
  moves: ["e7e6", "e2e4"],
  ponder: "d2d4"
}
iex(3)>

```