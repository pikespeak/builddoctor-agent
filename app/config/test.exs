import Config

config :builddoctor, Oban, testing: :manual

config :builddoctor,
  agent_token: "test-agent-token-0123456789abcdef",
  requester_key: "test-requester-key-0123456789abcdef",
  test_phase_until: nil,
  edge_secret: "test-edge-secret-0123456789abcdefgh"

config :ash,
  policies: [show_policy_breakdowns?: true],
  keyset_signing_secret: "81zARCKokxYX0mpwizieQuQzDtmuatB6YDUuV+wusH4",
  disable_async?: true

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :builddoctor, Builddoctor.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "builddoctor_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :builddoctor, BuilddoctorWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "8YF+owr29Qb0rZ73lZImF7bNbP5Su38ewYR1KNb3lqbSlLvkGjv1L1HVOklGvlH/",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
