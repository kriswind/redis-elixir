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
    # ensures that we don't run into 'Address already in use' errors by setting the socket to reuse the address
    {:ok, socket} = :gen_tcp.listen(6379, [:binary, active: false, reuseaddr: true])
    # Accept incoming connections and handle them asynchronously
    accept_client(socket)
  end

  defp accept_client(socket) do
    # Accept a client connection
    {:ok, client} = :gen_tcp.accept(socket)
    # Start a task to serve the client asynchronously
    Task.start_link(fn -> serve(client) end)
    # Log Client Connections
    IO.puts("Client connected: #{inspect(client)}")
    # Recursively call accept_client to handle multiple clients
    accept_client(socket)
  end

  defp serve(client) do
    # Receive data from the client
    case :gen_tcp.recv(client, 0) do
      {:ok, data} ->
        # Handle the response
        handle_response(client, data)
        # Recursively call serve to handle multiple requests from the same client
        serve(client)
      {:error, reason} ->
        # Log the error and close the client connection
        IO.puts("#{inspect(reason)} from #{inspect(client)}")
        :gen_tcp.close(client)
    end
  end

  defp handle_response(client, data) do
    # Split the data by "\r\n" to handle redis commands
    case String.split(data, "\r\n") do
      [_, _, command, _] ->
        case String.downcase(command) do
          # Reply to ping command with +PONG
          "ping" -> :gen_tcp.send(client, "+PONG\r\n")
          _ -> :gen_tcp.send(client, "$-1\r\n")
        end
      [_, _, command, len, arg, _] ->
        case String.downcase(command) do
          # Reply to echo command with the same argument
          "echo" -> :gen_tcp.send(client, "#{len}\r\n#{arg}\r\n")
          # call the handle_get function to query the ETS table for a matching value
          "get" -> handle_get(client, arg)
          # If the command is not recognized, send (nil) as a reply
          _ -> :gen_tcp.send(client, "$-1\r\n")
        end
      [_, _, command, _, arg1, _, arg2, _] ->
        case String.downcase(command) do
          "set" -> handle_set(client, arg1, arg2)
          _ -> :gen_tcp.send(client, "$-1\r\n")
        end
      [_, _, command, _, arg1, _, arg2, _, arg3, _, arg4, _] ->
        case String.downcase(command) do
          "set" -> handle_set(client, arg1, arg2, arg3, arg4)
          _ -> :gen_tcp.send(client, "$-1\r\n")
        end
      _ -> :gen_tcp.send(client, "$-1\r\n")
    end
  end

  defp handle_set(client, key, value) do
    # Insert the key-value pair into the ETS table
    :ets.insert(:redis_db, {key, value})
    # Send a "+OK" reply to the client
    :gen_tcp.send(client, "+OK\r\n")
  end

  defp handle_set(client, key, value, option, expiry_ms) do
    case String.downcase(option) do
      # If the option is "px", set the expiry time in milliseconds
      "px" ->
        # Convert the expiry time to an integer
        exp = String.to_integer(expiry_ms)
        # Ensure the expiry time is between 0 and 1000000 ms
        if (exp > 0 and exp < 1000000) do
          # Insert the key-value pair into the ETS table
          :ets.insert(:redis_db, {key, value})
          # Send a "+OK" reply to the client
          :gen_tcp.send(client, "+OK\r\n")
          # Spawn a new task to delete the key after the expiry time
          spawn(fn ->
            :timer.sleep(exp)
            :ets.delete(:redis_db, key)
          end)
        else
          # Send an error reply if the expiry time is invalid
          :gen_tcp.send(client, "$1\r\nExpiry time must be between 0 and 1000000 ms\r\n")
        end
      _ ->
        # Send an error reply if the option is invalid
        :gen_tcp.send(client, "$1\r\nInvalid option\r\n")
    end
  end

  defp handle_get(client, key) do
    case :ets.lookup(:redis_db, key) do
      [{^key, value}] -> :gen_tcp.send(client, "$#{String.length(value)}\r\n#{value}\r\n")
      _ -> :gen_tcp.send(client, "$-1\r\n")
    end
  end

end
