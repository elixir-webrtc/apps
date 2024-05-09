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

ip = System.get_env("BCR_IP", "127.0.0.1") |> ConfigParser.parse_ip!()
port = System.get_env("BCR_PORT", "5002") |> ConfigParser.parse_port!()
host = System.get_env("BCR_HOST", "http://localhost:#{port}")
token = System.get_env("BCR_TOKEN", "test")
admin_username = System.get_env("BCR_ADMIN_USERNAME", "admin")
admin_password = System.get_env("BCR_ADMIN_PASSWORD", "admin")

config :broadcaster,
  ip: ip,
  port: port,
  token: token,
  host: host,
  admin_username: admin_username,
  admin_password: admin_password
