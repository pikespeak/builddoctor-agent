defmodule BuilddoctorWeb.LegalHTML do
  @moduledoc false
  use BuilddoctorWeb, :html

  def imprint(assigns) do
    ~H"""
    <main class="mx-auto grid max-w-3xl gap-6 px-4 py-6">
      <Layouts.brand />
      <h1 class="font-display text-4xl font-bold">Imprint</h1>
      <.contact who={@who} />
      <div :if={@who} class="grid gap-2">
        <p :for={note <- @who.notes}>{note}</p>
      </div>
      <Layouts.legal />
    </main>
    """
  end

  def privacy(assigns) do
    ~H"""
    <main class="mx-auto grid max-w-3xl gap-6 px-4 py-6">
      <Layouts.brand />
      <h1 class="font-display text-4xl font-bold">Privacy</h1>
      <p>As of November 24, 2026. This page has no accounts, no advertising and no analytics.</p>
      <.part title="Who is responsible">
        <.contact who={@who} />
      </.part>
      <.part title="When you open the page">
        <p>
          The site runs on a Fly.io Sprite. Your IP address and request are processed to serve the site. Our own log keeps the time, the address of the page inside this site and technical details, but not your IP address. What Fly.io records is described in <a
            class="underline"
            href="https://fly.io/legal/privacy-policy/"
            rel="noopener"
          >its privacy policy</a>. The legal basis is our legitimate interest in running this page safely (Art. 6(1)(f) GDPR).
        </p>
      </.part>
      <.part title="Cookie and browser storage">
        <p>
          One signed cookie protects forms and, for the operator, holds the time of the sign-in. The site's JavaScript uses browser storage to keep the live connection working. Both are technically necessary. Nothing is used to follow you.
        </p>
      </.part>
      <.part title="When you enter a project">
        <p>
          We do not store who entered it. We store the name and commit of the project, workflow details (the complete file before and after, if a change is proposed), job times, computed facts, findings, proposed workflow changes, review decisions, events and records of model use. Public results include the facts, the findings and changes that passed the council, and every measured change; some records are visible to the operator or the agent only. From GitHub we request public data of the project: metadata, workflow files, runs, jobs, steps, commit IDs and check-run annotations. GitHub therefore learns which project we read. These data can contain names that their authors made public. Only for our own test project do we also write branches and start runs. The legal basis is our legitimate interest in examining public pipelines (Art. 6(1)(f) GDPR).
        </p>
      </.part>
      <.part title="Models">
        <p>
          We send the workflow file, job names, results and times, and the computed facts to OpenAI through a Fly.io connector. For the review we also send the findings and proposed changes. The requests ask OpenAI not to store the response for later retrieval. We do not include data of your visit, but public repository content can contain personal information. See <a
            class="underline"
            href="https://openai.com/policies/privacy-policy/"
            rel="noopener"
          >OpenAI's privacy policy</a>.
        </p>
      </.part>
      <.part title="Storage and backups">
        <p>
          Results stay until they are removed. Database backups are stored on the Sprite, where the seven newest are kept, and in the storage service Tigris, where they are not deleted automatically. Removing a project does not remove it from the backups; that is a separate manual step, which you can ask for.
        </p>
      </.part>
      <.part title="Other countries">
        <p>
          Fly.io, OpenAI, GitHub and Tigris are based in the United States or may process data there.
        </p>
      </.part>
      <.part title="Your rights">
        <p>
          You can ask for access, correction, deletion and restriction, and object to the processing. You can also complain to a data protection authority. Maintainers can ask us to remove their project at any time; an email is enough.
        </p>
      </.part>
      <Layouts.legal />
    </main>
    """
  end

  attr :title, :string, required: true
  slot :inner_block, required: true

  defp part(assigns) do
    ~H"""
    <section class="grid gap-2">
      <h2 class="font-display text-2xl font-bold">{@title}</h2>
      {render_slot(@inner_block)}
    </section>
    """
  end

  defp contact(assigns) do
    ~H"""
    <p :if={@who == nil}>The operator of this site has not provided contact details yet.</p>
    <address :if={@who} id="contact" class="grid not-italic">
      <span :for={line <- @who.lines}>{line}</span>
      <span :if={@who.phone}>Phone: {@who.phone}</span>
      <span>
        Email: <a class="inline-block py-2 underline" href={"mailto:#{@who.email}"}>{@who.email}</a>
      </span>
    </address>
    """
  end
end
