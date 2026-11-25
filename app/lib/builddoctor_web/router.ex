defmodule BuilddoctorWeb.Router do
  use BuilddoctorWeb, :router

  # Nothing from elsewhere; inline styles are needed for the bars and the picture.
  @headers %{
    "content-security-policy" =>
      "default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; " <>
        "connect-src 'self'; font-src 'self'; form-action 'self'; base-uri 'self'; frame-ancestors 'none'",
    "permissions-policy" =>
      "camera=(), microphone=(), geolocation=(), payment=(), usb=(), clipboard-write=(self)",
    "cross-origin-opener-policy" => "same-origin"
  }

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {BuilddoctorWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers, @headers
    plug BuilddoctorWeb.Visitor
    plug :not_listed
  end

  # Search engines shall not list results about projects of others.
  defp not_listed(%{path_info: ["a" | _]} = conn, _),
    do: Plug.Conn.put_resp_header(conn, "x-robots-tag", "noindex, nofollow")

  defp not_listed(conn, _), do: conn

  pipeline :api do
    plug :accepts, ["json"]
    plug BuilddoctorWeb.AgentAuth
  end

  # Bytes have their own limit; the secret is checked before they are read.
  pipeline :upload do
    plug BuilddoctorWeb.AgentAuth
  end

  scope "/api", BuilddoctorWeb do
    pipe_through [:upload]

    put "/pictures/:id/:part", PictureController, :store
  end

  scope "/api/json" do
    pipe_through [:api]

    forward "/", BuilddoctorWeb.AshJsonApiRouter
  end

  scope "/", BuilddoctorWeb do
    pipe_through :browser

    get "/imprint", LegalController, :imprint
    get "/privacy", LegalController, :privacy
    get "/requester", RequesterController, :new
    post "/requester", RequesterController, :create
    post "/requester/leave", RequesterController, :leave
    get "/a/:id/change.patch", PatchController, :patch
    get "/a/:id/photo/:file", PictureController, :show

    live_session :pages do
      live "/", FrontLive, :index
      live "/archive", ArchiveLive, :index
      live "/how-it-works", HowLive, :show
      live "/a/:id", AuditLive, :show
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", BuilddoctorWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard in development
  if Application.compile_env(:builddoctor, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: BuilddoctorWeb.Telemetry
    end
  end
end
