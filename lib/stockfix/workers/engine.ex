defmodule Stockfix.Workers.Engine do
  use GenServer
  require Logger

  @default_filename "stockfish-10-64"
  @default_exec_name "#{:code.priv_dir(:stockfix)}/#{@default_filename}"
  @max_time :infinity

  alias __MODULE__

  defstruct [
    port: nil,
    options: [],
    header: nil
  ]

  ###############################
  # API
  ###############################

  def start_link(args \\ []), do: GenServer.start_link(__MODULE__, args)

  # stop is already taken... use quit instead!
  def quit(pid), do: GenServer.cast(pid, :quit)

  def get_header(pid), do: GenServer.call(pid, :get_header)

  def get_options(pid), do: GenServer.call(pid, :get_options)

  def get_info(pid), do: GenServer.call(pid, :get_info)

  def is_ready(pid), do: GenServer.call(pid, :isready)

  def set_option(pid, name), do: GenServer.call(pid, "setoption name #{name}")

  def set_option(pid, name, value),
    do: GenServer.call(pid, "setoption name #{name} value #{value}")

  def uci_new_game(pid), do: GenServer.call(pid, "ucinewgame")

  def position(pid, :startfen), do: GenServer.call(pid, "position startpos")

  def position(pid, fen), do: GenServer.call(pid, "position fen #{fen}")

  def position(pid, fen, moves) when is_list(moves) do
    moves_string = Enum.join(moves, " ")
    position(pid, fen, moves_string)
  end

  def position(pid, fen, moves) when is_binary(moves),
    do: GenServer.call(pid, "position fen #{fen} moves #{moves}")

  def go(pid, options \\ []), do: GenServer.call(pid, {:go, options}, @max_time)

  def stop(pid), do: GenServer.call(pid, "stop")

  def ponderhit(pid), do: GenServer.call(pid, "ponderhit")

  # Stockfish specific
  def d(pid) do
    GenServer.call(pid, :d)
  end

  def call(pid, command), do: GenServer.call(pid, command)

  def cast(pid, command), do: GenServer.cast(pid, command)

  ###############################
  # SERVER CALLBACKS
  ###############################

  @impl true
  def init(args) do
    Process.flag(:trap_exit, true)
    {:ok, %Engine{}, {:continue, {:init_state, args}}}
  end

  @impl true
  def handle_continue({:init_state, args}, state) when is_list(args) do
    handle_continue({:init_state, Enum.into(args, %{})}, state)
  end
  def handle_continue({:init_state, args}, state) when is_map(args) do
    exec_name = Map.get(args, :exec_name, @default_exec_name)
    port = Port.open({:spawn, exec_name}, [{:line, 4096}, :binary, :use_stdio])

    case initialize_uci(port) do
      {_header, :timeout} ->
        {:stop, "Bad engine initialization"}
      {header, options} ->
        {:noreply, %{state | port: port, header: header, options: options}}
    end
  end

  # CALL
  ###############################

  @impl true
  def handle_call(:get_header, _from, %Engine{header: header} = state) do
    {:reply, header, state}
  end

  @impl true
  def handle_call(:get_options, _from, %Engine{options: options} = state) do
    {:reply, options, state}
  end

  @impl true
  def handle_call(:get_info, _from, %Engine{port: port} = state) do
    {:reply, Port.info(port), state}
  end

  @impl true
  def handle_call(:isready, _from, %Engine{port: port} = state) do
    send_command(port, "isready")
    receive do
      {^port, {:data, {:eol, "readyok"}}} ->
        {:reply, :readyok, state}
    after 10_000 ->
      {:stop, "engine timeout", :timeout, state}
    end
  end

  @impl true
  def handle_call({:go, options}, _from, %Engine{port: port} = state) do
    command = build_go_option_line(options)
    send_command(port, command)
    case go_loop(port, []) do
      :timeout -> {:stop, "engine unresponsive", state}
      data -> {:reply, data, state}
    end
  end

  @impl true
  def handle_call(:d, _from, %Engine{port: port} = state) do
    send_command(port, "d")
    case d_loop(port, []) do
      :timeout -> {:stop, "engine unresponsive", state}
      data -> {:reply, data, state}
    end
  end

  @impl true
  def handle_call(command, _from, %Engine{port: port} = state) when is_binary(command) do
    Logger.debug fn -> "execute call command : #{command}" end
    send_command(port, command)
    {:reply, :ok, state}
  end

  # CAST
  ###############################

  @impl true
  def handle_cast(command, %Engine{port: port} = state) when is_binary(command) do
    Logger.debug fn -> "execute cast command : #{command}" end
    send_command(port, command)
    {:noreply, state}
  end

  @impl true
  def handle_cast(:quit, %Engine{port: port} = state) do
    send_command(port, "quit")
    Port.close(port)
    {:stop, :normal, state}
  end

  # INFO
  ###############################

  @impl true
  def handle_info({:EXIT, port, reason}, %Engine{port: port} = state) do
    # Detect when the port is terminated
    Logger.debug fn -> "#{inspect port} port_terminated : #{inspect(reason)}" end
    {:stop, reason, state}
  end

  @impl true
  def terminate(reason, %Engine{} = _state) do
    Logger.debug fn -> "#{__MODULE__} is stopping : #{inspect(reason)}" end
    :ok
  end

  # PRIVATE
  ###############################

  defp send_command(port, command) do
    send(port, {self(), {:command, command <> "\n"}})
  end

  defp initialize_uci(port) do
    header = receive do
      {^port, {:data, {:eol, data}}} -> data
    after 1_000 -> :none
    end

    # order is important!
    send_command(port, "uci")
    options = options_loop(port, [])

    {header, options}
  end

  defp options_loop(port, acc) do
    receive do
      {^port, {:data, {:eol, "uciok"}}} ->
        acc
      {^port, {:data, {:eol, option}}} ->
        options_loop(port, [option | acc])
    after 2_000 ->
      :timeout
    end
  end

  defp go_loop(port, acc) do
    receive do
      # {_, :stop} ->
      #   send_command(port, "stop")
      #   acc
      # {_, :ponderhit} ->
      #   send_command(port, "ponderhit")
      #   acc

      {^port, {:data, {:eol, "bestmove " <> _rest = line}}} ->
        [{DateTime.utc_now(), line} | acc]
      {^port, {:data, {:eol, data}}} ->
        date_time = DateTime.utc_now()
        Logger.debug fn -> "#{date_time} #{inspect data}" end
        go_loop(port, [{date_time, data} | acc])
    after 60_000 ->
      :timeout
    end
  end

  defp d_loop(port, acc) do
    receive do
      {^port, {:data, {:eol, "Checkers:" <> _rest = line}}} ->
        [line | acc]
      {^port, {:data, {:eol, data}}} ->
        Logger.debug fn -> "d_loop #{inspect data}" end
        d_loop(port, [data | acc])
    after 20_000 ->
      :timeout
    end
  end

  defp build_go_option_line(options) do
    possible_options = ~w(
      searchmoves ponder wtime btime winc binc
      movestogo depth nodes mate movetime infinite
    )a

    options |> Enum.reduce("go", fn {k, _v} = option, acc ->
      if Enum.member?(possible_options, k) do
        case option do
          {_, :undefined} -> acc
          {:infinite, _value} -> acc <> " infinite"
          {:ponder, value} -> acc <> " ponder #{value}"
          {key, value} when is_list(value) -> acc <> " #{key} #{Enum.join(value, " ")}"
          {key, value} -> acc <> " #{key} #{value}"
        end
      else
        acc
      end
    end)
  end
end
