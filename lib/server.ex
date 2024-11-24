defmodule Server do
  @moduledoc """
  Your implementation of a Redis server
  """

  use Application

  def start(_type, _args) do
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
    msg = :gen_tcp.recv(client, 0)
    case msg do
      {:ok, data} -> handle_response(client, data)
      {:error, _} -> :gen_tcp.close(client)
    end

    serve(client)
  end

  defp handle_response(client, data) do
    case String.split(data, "\r\n") do
      [_, _, command, _] ->
        case String.downcase(command) do
          "ping" -> :gen_tcp.send(client, "+PONG\r\n")
          _ -> :gen_tcp.send(client, "-ERR unknown command\r\n")
        end
      [_, _, command, len, message, _] ->
        case String.downcase(command) do
          "echo" -> :gen_tcp.send(client, "#{len}\r\n#{message}\r\n")
          _ -> :gen_tcp.send(client, "-ERR unknown command\r\n")
        end
      _ -> :gen_tcp.send(client, "-ERR unknown command\r\n")
    end
    serve(client)
  end

end
