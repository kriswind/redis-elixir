defmodule Server do
  @moduledoc """
  Your implementation of a Redis server
  """

  use Application

  def start(_type, _args) do
    # Initialize ETS table for storing key-value pairs
    :ets.new(:redis_db, [:set, :public, :named_table])

    Supervisor.start_link([{Task, fn -> Server.listen() end}], strategy: :one_for_one)
  end

  @doc """
  Listen for incoming connections
  """
  def listen() do
    # Since the tester restarts your program quite often, setting SO_REUSEADDR
    # ensures that we don't run into 'Address already in use' errors
    {:ok, socket} = :gen_tcp.listen(6379, [:binary, active: false, reuseaddr: true])

    accept_client(socket)

  end

  defp accept_client(socket) do
    {:ok, client} = :gen_tcp.accept(socket)
    Task.start_link(fn -> serve(client) end)
    accept_client(socket)
  end

  defp serve(client) do
    case :gen_tcp.recv(client, 0) do
      {:ok, data} ->
        handle_response(client, data)
        serve(client)
      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}")
        :gen_tcp.close(client)
    end
  end

  defp handle_response(client, data) do
    case String.split(data, "\r\n") do
      [_, _, command, _] ->
        case String.downcase(command) do
          "ping" -> :gen_tcp.send(client, "+PONG\r\n")
          _ -> :gen_tcp.send(client, "$-1\r\n")
        end
      [_, _, command, len, arg, _] ->
        case String.downcase(command) do
          "echo" -> :gen_tcp.send(client, "#{len}\r\n#{arg}\r\n")
          "get" -> handle_get(client, arg)
          _ -> :gen_tcp.send(client, "$-1\r\n")
        end
      [_, _, command, _, arg1, _, arg2, _] ->
        case String.downcase(command) do
          "set" -> handle_set(client, arg1, arg2)
          _ -> :gen_tcp.send(client, "$-1\r\n")
        end
      _ -> :gen_tcp.send(client, "$-1\r\n")
    end
  end

  defp handle_set(client, key, value) do
    :ets.insert(:redis_db, {key, value})
    :gen_tcp.send(client, "+OK\r\n")
  end

  defp handle_get(client, key) do
    case :ets.lookup(:redis_db, key) do
      [{^key, value}] -> :gen_tcp.send(client, "$#{String.length(value)}\r\n#{value}\r\n")
      _ -> :gen_tcp.send(client, "$-1\r\n")
    end
  end

end
