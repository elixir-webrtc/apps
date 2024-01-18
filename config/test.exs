import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :reco, RecoWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "ZYtW2ZgK0A3i9LYgDOVKzzL/vmPUuXJIjPzKORJJebEEdgqbF6b4oLHCv2jXMOqQ",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime
