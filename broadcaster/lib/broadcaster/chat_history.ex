defmodule Broadcaster.ChatHistory do
  @moduledoc false
  use Agent

  @max_history_size 100

  @spec start_link(term()) :: Agent.on_start()
  def start_link(_) do
    Agent.start_link(fn -> %{size: 0, queue: :queue.new()} end, name: __MODULE__)
  end

  @spec put(map()) :: :ok
  def put(msg) do
    Agent.cast(__MODULE__, fn history ->
      queue = :queue.in(msg, history.queue)

      if history.size == @max_history_size do
        {_, queue} = :queue.out(history.queue)
        %{history | queue: queue}
      else
        %{history | size: history.size + 1, queue: queue}
      end
    end)
  end

  @spec get() :: [map()]
  def get() do
    try do
      Agent.get(__MODULE__, fn history -> :queue.to_list(history.queue) end, 1000)
    catch
      :exit, _ -> []
    end
  end

  @spec delete(String.t()) :: :ok
  def delete(id) do
    Agent.update(__MODULE__, fn history ->
      queue = :queue.delete_with(fn msg -> msg.id == id end, history.queue)
      %{history | size: history.size - 1, queue: queue}
    end)
  end
end
