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
        As of November 25, 2026. No visitor account is required. There is no advertising by others. Analytics runs only if you accept it.
      </p>
      <.part title="Who is responsible">
        <.contact who={@who} />
      </.part>
      <.part title="When you open the page">
        <p>
          The site runs on a Fly.io Sprite; a small Fly.io machine may pass your request on to it, together with your IP address. Your IP address and request are processed to serve the site. Our examination records do not identify the visitor. Our application log keeps the time, the address of the page inside this site, what you enter into the form and technical details; handling a request also involves connection data at our hosting provider. What Fly.io records is described in <a
            class="underline"
            href="https://fly.io/legal/privacy-policy/"
            rel="noopener"
          >its privacy policy</a>. The legal basis is our legitimate interest in running this page safely (Art. 6(1)(f) GDPR).
        </p>
      </.part>
      <.part title="Cookie and browser storage">
        <p>
          The session cookie _builddoctor_key protects forms and, for the operator, holds the time of the sign-in. It expires when your browser session ends. The site's JavaScript uses session storage and local storage to recover the live connection and to navigate. We consider this strictly necessary for the service you asked for (Section 25(2) no. 2 TDDDG). The same applies to your answer about analytics, which is kept in local storage until you delete it there.
        </p>
      </.part>
      <.part id="analytics" title="Analytics, only with your consent">
        <p>
          If you accept, your browser loads PostHog from our site and sends usage data to r.builddoctor.app, our PostHog proxy hosted on Cloudflare, and from there to PostHog, Inc., which processes them for us in its EU cloud. Before you consent, PostHog is not loaded and no analytics data are sent. If your browser sends Do Not Track or Global Privacy Control, we count this as a no. The operator is not measured while signed in.
        </p>
        <p>
          The data are: the kind of page, without its query and without the ID of an edition; how long and how far it was read; named controls that were used; the domain you came from and which of our own posts you followed; random IDs for browser and visit; browser, operating system, device type, language, time zone and window size; and the time. We leave out what you type, page titles, texts and project names. There are no session recordings. Your IP address reaches PostHog when the data are sent; we have set PostHog to discard it and not to derive a place from it.
        </p>
        <p>
          PostHog keeps the random IDs and the visit in local and session storage. The purpose is to learn how the page is used and to improve it. The legal basis is your consent (Section 25(1) TDDDG, Art. 6(1)(a) GDPR). It is voluntary, and you can withdraw it at any time with “Analytics choice” at the bottom of the page; this stops the sending and deletes PostHog's data in this browser. Withdrawing consent does not affect processing that took place before you withdrew it. Events are set to be kept in our PostHog project for 12 months; PostHog then deletes them during its cleanups, which can take up to about two more months. See <a
            class="underline"
            href="https://posthog.com/privacy"
            rel="noopener"
          >PostHog's privacy policy</a>.
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
        <p>
          For a second opinion we send the sentences and advice of published findings and the facts they cite, with email addresses removed, to TypeSafe through a Fly.io connector. Its model answers with probabilities, which we store and show. We do not include the workflow file or data about your visit. See <a
            class="underline"
            href="https://typesafe.ai/legal/privacy-policy"
            rel="noopener"
          >TypeSafe's privacy policy</a>.
        </p>
      </.part>
      <.part title="Notifications when an examination starts">
        <p>
          When an examination starts, our server emails the operator the name of the project, whether a visitor or the operator started it, and the time. The email is sent by Plus Five Five, Inc. (Resend) through a Fly.io connector. This also happens if you decline analytics. We do not include your IP address, cookies or browser identifiers. Our legitimate interest (Art. 6(1)(f) GDPR) is to notice use and problems quickly. Resend keeps sent emails for 30 days and stores its data in the United States; the operator keeps the emails in the mailbox. See <a
            class="underline"
            href="https://resend.com/legal/privacy-policy"
            rel="noopener"
          >Resend's privacy policy</a>.
        </p>
      </.part>
      <.part title="When you write to us">
        <p>
          We use your message and email address to answer you. If you ask for a place on the waiting list for private editions, we keep your address in our mailbox and use it only to write to you about them, until you ask us to remove it or we give up the plan. The legal basis is your consent (Art. 6(1)(a) GDPR); you can withdraw it at any time by email. Withdrawing it does not affect the processing before. Cloudflare receives and forwards the mail and answers DNS queries for the domain. A feed reader that follows a project sends us requests like any other visit; we keep no list of followers.
        </p>
      </.part>
      <.part title="Storage and backups">
        <p>
          Examinations of other projects are deleted after 90 days, and database backups on the Sprite and in the storage service Tigris after 30 days; the three newest backups in each storage location are always kept. Application logs remain on the Sprite and are trimmed manually. The Sprite sleeps when nobody uses it, so a deletion can happen later, when it wakes up. Our own measured trials stay as long as the project runs. If you ask for a removal, we also remove the project from the backups by hand.
        </p>
      </.part>
      <.part title="Other countries">
        <p>
          Fly.io, OpenAI, TypeSafe, GitHub, Tigris, Cloudflare, Resend and, if you accept analytics, PostHog are based in the United States or may process data there.
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

  attr :id, :string, default: nil
  attr :title, :string, required: true
  slot :inner_block, required: true

  defp part(assigns) do
    ~H"""
    <section id={@id} class="grid gap-2">
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
