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
      <p>
        As of November 24, 2026. No visitor account is required. There is no advertising and no analytics.
      </p>
      <.part title="Who is responsible">
        <.contact who={@who} />
      </.part>
      <.part title="When you open the page">
        <p>
          The site runs on a Fly.io Sprite. Your IP address and request are processed to serve the site. Our examination records do not identify the visitor. Our application log keeps the time, the address of the page inside this site, what you enter into the form and technical details; handling a request also involves connection data at our hosting provider. What Fly.io records is described in <a
            class="underline"
            href="https://fly.io/legal/privacy-policy/"
            rel="noopener"
          >its privacy policy</a>. The legal basis is our legitimate interest in running this page safely (Art. 6(1)(f) GDPR).
        </p>
      </.part>
      <.part title="Cookie and browser storage">
        <p>
          The session cookie _builddoctor_key protects forms and, for the operator, holds the time of the sign-in. It expires when your browser session ends. The site's JavaScript uses session storage and local storage to recover the live connection and to navigate. We consider this strictly necessary for the service you asked for (Section 25(2) no. 2 TDDDG). Nothing is used to follow you.
        </p>
      </.part>
      <.part title="When you enter a project">
        <p>
          To share the daily limit fairly, we keep a keyed hash of your IP address (for IPv6, of its first half) in the session cookie and count your starts in memory, at most until the next day or restart. In our database we do not store who entered it. We store the name and commit of the project, workflow details (the complete file before and after, if a change is proposed), job times, computed facts, findings, proposed workflow changes, review decisions, generated pictures and lines, events and records of model use. Public results include the facts, a computed grade, the generated pictures and lines, the findings and changes that passed the council, and every measured change; some records are visible to the operator or the agent only. From GitHub we request public data of the project: metadata, workflow files, runs, jobs, steps, commit IDs and check-run annotations. GitHub therefore learns which project we read. These data may contain names, usernames, email addresses and other personal information, including information about people who did not enter the project. Only for our own test project do we also write branches and start runs. Our legitimate interests (Art. 6(1)(f) GDPR) are to analyze public CI workflows, to suggest improvements with the help of AI and to show measured results publicly.
        </p>
      </.part>
      <.part title="Models">
        <p>
          We send the workflow file, job names, results and times, and the computed facts to OpenAI through a Fly.io connector. For the review we also send the findings and proposed changes. To choose a figure for the press photos, we also send the project's public description, main language and topics. An editor model receives findings and their facts before the council has decided whether to publish them, and drafts headlines, captions and photo scenes. The photos are made by an OpenAI image model; its requests combine fixed text with an approved scene written by the editor, or a fallback scene from a fixed list. The requests ask OpenAI not to store the response for later retrieval. This does not by itself prevent retention for abuse monitoring or other operational purposes. We do not include data about your visit, but public repository content can contain personal information. See <a
            class="underline"
            href="https://openai.com/policies/privacy-policy/"
            rel="noopener"
          >OpenAI's privacy policy</a>.
        </p>
      </.part>
      <.part title="Storage and backups">
        <p>
          Examinations of other projects are deleted after 90 days, and database backups on the Sprite and in the storage service Tigris after 30 days; the three newest backups in each storage location are always kept. Application logs remain on the Sprite and are trimmed manually. The Sprite sleeps when nobody uses it, so a deletion can happen later, when it wakes up. Our own measured trials stay as long as the project runs. If you ask for a removal, we also remove the project from the backups by hand.
        </p>
      </.part>
      <.part title="Other countries">
        <p>
          Fly.io, OpenAI, GitHub and Tigris are based in the United States or may process data there.
        </p>
      </.part>
      <.part title="Your right to object">
        <p class="font-bold">
          You may object at any time, on grounds relating to your particular situation, to processing based on Art. 6(1)(f) GDPR, by writing to the email address above. We will stop that processing unless we demonstrate compelling legitimate grounds that override your interests, rights and freedoms, or need the data for legal claims. This applies to everybody whose data are concerned, not only to maintainers.
        </p>
      </.part>
      <.part title="Your rights">
        <p>
          You can ask for access, correction, deletion, restriction and data portability under the conditions of the GDPR. You can also complain to a data protection authority. Maintainers can ask us to remove their project at any time; an email is enough.
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
