defmodule Broadcaster.RecorderSupervisor do
  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def start_recorder() do
    DynamicSupervisor.start_child(__MODULE__, Broadcaster.Recorder)
  end

  def recorder_alive?() do
    GenServer.whereis(Broadcaster.Recorder) != nil
  end

  def terminate_recorder(reason \\ :normal) do
    GenServer.stop(Broadcaster.Recorder, reason)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
