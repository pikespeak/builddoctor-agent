defmodule Builddoctor.Expire do
  @moduledoc "Lets Ash remove what is older than its period."
  use Oban.Worker, queue: :default, max_attempts: 3, unique: [period: 600]

  @impl true
  def perform(_job) do
    {:ok, _} = Builddoctor.Bench.expire_audits(authorize?: false)
    :ok
  end
end
