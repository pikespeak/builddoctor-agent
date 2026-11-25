// Loaded by consent.js, only after somebody accepted. It sends how pages are used, never which
// project: addresses of editions lose their id, queries and titles and texts are left out.
import posthog from "../vendor/posthog"

// Everything else the library knows is dropped.
const KEPT = new Set([
  "token", "distinct_id", "$device_id", "$session_id", "$window_id", "$pageview_id", "$insert_id", "$time",
  "$lib", "$lib_version", "$process_person_profile", "$is_identified",
  "$host", "$pathname", "$current_url", "$prev_pageview_pathname", "$prev_pageview_duration",
  "$prev_pageview_id", "$prev_pageview_max_scroll_percentage", "$prev_pageview_max_content_percentage",
  "$referring_domain", "$session_entry_referring_domain",
  "$browser", "$browser_version", "$os", "$os_version", "$device_type",
  "$viewport_width", "$viewport_height", "$browser_language_prefix", "$timezone",
  "control",
  "utm_source",
])

// Only our own labels; a link of somebody else could carry anything.
const SOURCES = ["x", "bluesky", "reddit", "hackernews", "linkedin", "github", "fly"]
const EVENTS = ["$pageview", "$pageleave", "control used"]

const page = path => path.replace(/^\/a\/[^/]+/, "/a/edition")

function clean(event) {
  if (!EVENTS.includes(event.event)) return null
  const properties = {}
  for (const [name, value] of Object.entries(event.properties)) if (KEPT.has(name)) properties[name] = value
  for (const name of ["$pathname", "$prev_pageview_pathname"])
    if (properties[name]) properties[name] = page(properties[name])
  if (properties.$current_url) {
    const url = new URL(properties.$current_url)
    properties.$current_url = url.origin + page(url.pathname)
  }
  if (!SOURCES.includes(properties.utm_source)) delete properties.utm_source
  // No place is derived from the address.
  properties.$geoip_disable = true
  return {...event, properties, $set: undefined, $set_once: undefined}
}

// Only controls with a fixed name; what stands on them or is typed is not read.
for (const type of ["click", "submit"])
  addEventListener(type, ({target}) => {
    const el = target instanceof Element && target.closest(type === "submit" ? "form[data-track]" : "[data-track]:not(form)")
    if (el) posthog.capture("control used", {control: el.dataset.track})
  }, true)

window.builddoctorAnalytics = {
  start({key, host}, allowed) {
    posthog.init(key, {
      api_host: host,
      defaults: "2026-01-30", // later ones write to the storage with a delay
      persistence: "localStorage",
      person_profiles: "never",
      capture_pageview: "history_change",
      capture_pageleave: true,
      autocapture: false, // its texts and links would name projects
      rageclick: false,
      capture_dead_clicks: false,
      capture_heatmaps: false,
      capture_performance: false,
      capture_exceptions: false,
      capture_webmcp: false,
      disable_session_recording: true,
      disable_surveys: true,
      disable_product_tours: true,
      disable_conversations: true,
      disable_web_experiments: true,
      disable_external_dependency_loading: true,
      advanced_disable_flags: true,
      opt_in_site_apps: false,
      // Nothing waits in a queue, so that nothing is sent after a withdrawal.
      request_batching: false,
      respect_dnt: true,
      before_send: event => event && allowed() ? clean(event) : null,
    })
  },
  stop() {
    posthog.opt_out_capturing()
    posthog.reset(true)
    // Otherwise it writes its state again when the page closes.
    posthog.set_config({disable_persistence: true})
  },
}
