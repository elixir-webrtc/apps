defmodule Broadcaster do
  @moduledoc """
  Broadcaster keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  @spec format_float(float()) :: binary()
  def format_float(float) do
    if trunc(float) == float do
      :erlang.float_to_binary(float, decimals: 0)
    else
      :erlang.float_to_binary(float, decimals: 1)
    end
  end
end
