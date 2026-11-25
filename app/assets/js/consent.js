// Asks before anything of PostHog is loaded. Without a key in the page it does nothing.
const CHOICE = "builddoctor-analytics"
const box = () => document.getElementById("analytics-consent")
const signal = () => navigator.globalPrivacyControl === true || [navigator.doNotTrack, window.doNotTrack].some(v => v === "1" || v === "yes")

function read() {
  try { return localStorage.getItem(CHOICE) } catch { return null }
}

function save(value) {
  try { localStorage.setItem(CHOICE, value) } catch { /* asked again next time */ }
}

const allowed = () => !signal() && read() === "yes"
let loading = null

function load(settings) {
  loading ||= new Promise((done, failed) => {
    const script = document.createElement("script")
    script.src = settings.src
    script.onload = done
    script.onerror = failed
    document.head.append(script)
  }).then(
    () => { if (allowed()) window.builddoctorAnalytics.start(settings, allowed) },
    () => { loading = null },
  )
}

// Deletes what PostHog kept in this browser.
function forget(key) {
  for (const store of ["localStorage", "sessionStorage"]) {
    try {
      const names = Object.keys(window[store])
      for (const name of names)
        if (/^(__)?ph_/.test(name) && name.includes(key)) window[store].removeItem(name)
    } catch { /* closed storage holds nothing */ }
  }
}

function show() {
  const el = box()
  el.dataset.signal = String(signal())
  el.hidden = false
}

export default function consent() {
  const el = box()
  const channel = new BroadcastChannel(CHOICE)
  // The Requester's pages and the sign-in have no box: open tabs of the visit before stop.
  if (!el) return channel.postMessage("stop")
  // Copies of the site under another name ask nothing and send nothing.
  if (!el || location.hostname !== el.dataset.site) return
  const settings = el.dataset
  document.documentElement.dataset.analytics = "offered"

  // The library goes with the page; a new page does not load it without consent.
  const quit = () => {
    if (window.builddoctorAnalytics) window.builddoctorAnalytics.stop()
    forget(settings.key)
    if (loading) location.reload()
  }
  // Also a tab without PostHog loads again, so that the server decides whether it may still ask.
  channel.onmessage = () => {
    quit()
    if (!loading) location.reload()
  }
  let opener = null
  const hide = () => {
    el.hidden = true
    if (opener?.isConnected) opener.focus()
    opener = null
  }
  const no = () => {
    save("no")
    hide()
    quit()
  }
  const yes = () => {
    save("yes")
    hide()
    if (allowed()) load(settings)
  }

  addEventListener("click", ({target}) => {
    const act = target instanceof Element && target.closest("[data-analytics-do]")
    if (!act) return
    switch (act.dataset.analyticsDo) {
      case "accept": return yes()
      case "decline": return no()
      case "close": return hide()
      case "open":
        opener = act
        show()
        el.focus()
    }
  })
  // Another tab of this browser decided.
  addEventListener("storage", e => {
    if (e.key !== CHOICE && e.key !== null) return
    if (!allowed() && loading) quit()
    else if (allowed()) { el.hidden = true; load(settings) }
    else if (read() === "no") el.hidden = true
  })

  if (allowed()) return load(settings)
  // A page that was still open may have written something while it closed.
  forget(settings.key)
  if (signal()) return
  if (read() !== "no") show()
}
