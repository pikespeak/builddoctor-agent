defmodule BuilddoctorWeb.Suggestion do
  @moduledoc """
  How a recommendation becomes a pull request of the person who wants it. BuildDoctor has no
  rights in foreign projects: GitHub makes the fork, and the person opens the pull request.
  Names, branch and path match the strict patterns of Ash, so they are safe in a command.
  """
  use BuilddoctorWeb, :html

  alias PetalComponents.Card

  attr :audit, :map, required: true
  attr :trial, :map, required: true

  def suggestion(assigns) do
    ~H"""
    <Card.card id="suggestion" class="border-bark bg-white p-4 sm:p-6">
      <h2 class="font-display text-2xl font-bold">Make it a pull request</h2>
      <p class="mt-2 max-w-prose">
        It is yours: BuildDoctor has no access to the project. Review the change first.
      </p>
      <p class="mt-2 max-w-prose">
        Read on {Calendar.strftime(@audit.inserted_at, "%B %-d, %Y")}{commit(@audit)}. The workflow may have changed since.
      </p>
      <p class="mt-4 flex flex-wrap gap-3">
        <PC.button
          link_type="a"
          to={edit_url(@audit)}
          target="_blank"
          rel="noopener"
          label="Edit on GitHub"
        />
        <PC.button
          link_type="a"
          to={~p"/a/#{@audit.id}/change.patch"}
          variant="outline"
          download
          label="Download the patch"
        />
      </p>
      <p class="mt-2 max-w-prose">
        The editor opens the workflow. GitHub makes your own fork if you need one. Make the marked changes there, then propose them.
      </p>
      <h3 class="mt-4 font-bold">All at once, with the GitHub command line</h3>
      <pre
        id="command"
        tabindex="0"
        role="region"
        aria-label="Command for a fork and a pull request"
        class="mt-2 overflow-x-auto border border-bark p-3 text-sm focus-visible:outline-3 focus-visible:outline-madder"
      ><code>{command(@audit, @trial)}</code></pre>
      <p class="mt-2">
        <PC.button
          type="button"
          variant="outline"
          label="Copy the command"
          phx-click={JS.dispatch("builddoctor:copy", detail: %{text: command(@audit, @trial)})}
        />
      </p>
      <p class="mt-2 max-w-prose">
        It makes a fork, a branch and the pull request. For a private copy or your own clone, apply the patch with <code>git apply</code>.
      </p>
    </Card.card>
    """
  end

  defp commit(%{base_sha: <<short::binary-size(7), _::binary>>}), do: " at commit #{short}"
  defp commit(_), do: ""

  def edit_url(audit),
    do:
      "https://github.com/#{audit.repository}/edit/#{audit.default_branch}/#{audit.workflow_path}"

  def command(audit, trial) do
    [_, name] = String.split(audit.repository, "/")
    page = url(~p"/a/#{audit.id}")

    note =
      if trial.verdict == :accepted,
        do: "Measured by BuildDoctor: #{page}",
        else: "Suggested by BuildDoctor, not measured: #{page}"

    """
    gh repo fork #{audit.repository} --clone --default-branch-only &&
    cd #{name} &&
    git switch -c builddoctor-suggestion &&
    curl -fsSL #{page}/change.patch | git apply &&
    git commit -am "Apply the BuildDoctor suggestion" &&
    git push -u origin builddoctor-suggestion &&
    gh pr create --repo #{audit.repository} --title "Improve the workflow" --body "#{note}"
    """
  end
end
