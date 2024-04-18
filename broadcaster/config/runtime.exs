import Config

defmodule ConfigParser do
  def parse_ip!(input) do
    input
    |> String.to_charlist()
    |> :inet.parse_address()
    |> case do
      {:ok, address} -> address
      {:error, _reason} -> raise "#{inspect(input)} is not a valid IP address"
    end
  end

  def parse_port!(input) do
    case Integer.parse(input) do
      {int, ""} when int in 0..65_536 -> int
      _other -> raise "#{inspect(input)} is not a valid port"
    end
  end
end

config :broadcaster,
  ip: System.get_env("BCR_IP", "0.0.0.0") |> ConfigParser.parse_ip!(),
  port: System.get_env("BCR_PORT", "5002") |> ConfigParser.parse_port!(),
  token: System.get_env("BCR_TOKEN", "test")
