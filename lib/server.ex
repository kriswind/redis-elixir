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
    serve(client)
    accept_client(socket)
  end

  defp serve(client) do
    msg = :gen_tcp.recv(client, 0)
    case msg do
      {:ok, _} -> :gen_tcp.send(client, "+PONG\r\n")
      {:error, _} -> :gen_tcp.close(client)
    end

    serve(client)
  end

end
