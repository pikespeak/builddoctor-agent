// Analytics with and without consent, in Chrome; nothing reaches PostHog, its address is answered here.
// Needs the app on localhost:4010 with posthog_key and posthog_host set and the project
// secretowner/secretproject on page 1 (test database).
//   PLAYWRIGHT_FROM=folder/node_modules node analytics.mjs SCREENSHOT_FOLDER
import {createRequire} from "module"
const {chromium} = createRequire(process.env.PLAYWRIGHT_FROM + "/")("playwright")
import zlib from "zlib"
const B="http://localhost:4010"; let bad=0
const ok=(n,c,x="")=>{console.log(c?"ok  ":"FAIL",n,x); if(!c)bad++}
const browser=await chromium.launch({channel:"chrome"})
async function ctx(init, status=200){
  const c=await browser.newContext({viewport:{width:1280,height:800},userAgent:"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36"}); await c.addInitScript(()=>Object.defineProperty(navigator,"webdriver",{get:()=>false})); const log={ph:[],an:0,err:[],ext:[]}
  if(init) await c.addInitScript(init)
  await c.route("**/*", async r=>{const u=r.request().url()
    if(u.startsWith(B)){ if(u.includes("analytics")&&u.endsWith(".js"))log.an++; return r.continue()}
    if(u.startsWith("https://r.builddoctor.app")){let b=r.request().postDataBuffer(); let t=""; if(b){try{t=zlib.gunzipSync(b).toString()}catch{t=b.toString(); if(t.startsWith("data="))t=Buffer.from(decodeURIComponent(t.slice(5)),"base64").toString()}}
      log.ph.push({u,t,m:r.request().method()}); if(status===0)return r.abort(); return r.fulfill({status,headers:{"access-control-allow-origin":"*","access-control-allow-headers":"*"},body:'{"status":1}',contentType:"application/json"})}
    log.ext.push(u); return r.abort()})
  const p=await c.newPage(); p.on("console",m=>{if(m.type()==="error"||/CSP|Content Security/.test(m.text()))log.err.push(m.text())}); p.on("pageerror",e=>log.err.push(String(e)))
  return {c,p,log}
}
const stored=p=>p.evaluate(()=>({l:Object.keys(localStorage),s:Object.keys(sessionStorage),c:document.cookie}))
const ph=o=>[...o.l,...o.s].filter(k=>/ph_|posthog/i.test(k))
const box=p=>p.locator("#analytics-consent")
const evs=log=>log.ph.flatMap(x=>{try{const j=JSON.parse(x.t);return Array.isArray(j)?j:(j.batch||j.data||[j])}catch{return[]}})
{ const {c,p,log}=await ctx(); await p.goto(B+"/?project=secretowner/typed&utm_source=typed-label&utm_campaign=secret"); await p.waitForTimeout(1500)
  ok("asked",await box(p).isVisible()); ok("nothing loaded or sent before",log.an===0&&log.ph.length===0); ok("nothing stored",ph(await stored(p)).length===0)
  const w=await p.locator(".consent-button:visible").evaluateAll(x=>x.map(e=>[e.offsetWidth,e.offsetHeight].join()))
  ok("same size",w.length===2&&w[0]===w[1],w); await p.screenshot({path:process.argv[2]+"/ask.png"})
  await p.setViewportSize({width:360,height:740}); await p.screenshot({path:process.argv[2]+"/ask360.png"}); await p.setViewportSize({width:1280,height:800})
  await p.click("[data-analytics-do=accept]"); await p.waitForTimeout(2500)
  ok("gone",!(await box(p).isVisible())); ok("loaded once",log.an===1); ok("pageview",evs(log).some(e=>e.event==="$pageview"))
  await p.fill("#project","typedowner/typedproject"); await p.click("#place-2"); await p.waitForTimeout(500)
  const id=(await p.locator("#project-1 a").getAttribute("href")).slice(3); await p.click("#project-1 a"); await p.waitForTimeout(2500)
  await p.evaluate(()=>window.dispatchEvent(new PageTransitionEvent("pagehide"))); await p.waitForTimeout(800); await p.goto(B+"/privacy#analytics"); await p.waitForTimeout(1500)
  const all=JSON.stringify(log.ph.map(x=>x.u+x.t))
  console.log([...new Set(log.ph.map(x=>x.m+" "+x.u.replace(/\?.*/,"")))]); console.log(evs(log).map(e=>e.event+" "+(e.properties?.$pathname)+" "+(e.properties?.control||"")))
  for(const s of ["secret","typed",id,"Daily"," title","$title","localhost:4010/?"]) ok("not sent: "+s,!all.includes(s))
  console.log("keys",[...new Set(evs(log).flatMap(e=>Object.keys(e.properties||{})))].join(" "))
  ok("no set, no profile",!all.includes("$set")&&evs(log).every(e=>e.properties.$process_person_profile===false)); ok("pageleave",evs(log).some(e=>e.event==="$pageleave")); ok("only events sent, no other endpoint",log.ph.every(x=>/\/(i\/v0\/)?e\/|\/batch/.test(x.u)),[...new Set(log.ph.map(x=>x.u.slice(0,60)))])
  ok("no cookie",!/ph_/.test((await stored(p)).c)); console.log("stored",await stored(p))
  ok("no foreign host",log.ext.length===0,log.ext); ok("no errors",log.err.length===0,log.err)
  const p2=await c.newPage(); await p2.goto(B+"/imprint"); await p2.waitForTimeout(1500); ok("second tab not asked",!(await box(p2).isVisible()))
  await p.click("[data-analytics-do=open]"); ok("choice opens",await box(p).isVisible()); const before=log.ph.length
  await p.click("[data-analytics-do=decline]"); await p.waitForTimeout(2500); const o=await stored(p)
  ok("nothing sent at or after withdrawal",log.ph.length===before,log.ph.slice(before).map(x=>x.t.slice(0,200))); ok("storage cleared",ph(o).length===0,JSON.stringify(o))
  ok("other tab stopped",await p2.evaluate(()=>!window.builddoctorAnalytics)); ok("this tab unloaded",await p.evaluate(()=>!window.builddoctorAnalytics))
  const n=log.ph.length; await p2.goto(B+"/archive"); await p.goto(B+"/how-it-works"); await p.waitForTimeout(1500); ok("stays off, not asked again",log.ph.length===n&&!(await box(p).isVisible())); ok("storage stays clear",ph(await stored(p)).length===0,JSON.stringify(await stored(p))); await c.close() }
{ const {c,p,log}=await ctx(); await p.goto(B+"/"); await p.click("[data-analytics-do=decline]"); await p.goto(B+"/imprint"); await p.waitForTimeout(1200)
  ok("declined: silent",log.an===0&&log.ph.length===0&&!(await box(p).isVisible())); await p.click("[data-analytics-do=open]"); await p.click("[data-analytics-do=accept]"); await p.waitForTimeout(1500); ok("can accept later",log.ph.length>0);
  await p.goto(B+"/?utm_source=reddit"); await p.waitForTimeout(1500); ok("own label kept",evs(log).some(e=>e.properties.utm_source==="reddit"));
  const r=await c.newPage(); const gone=p.waitForEvent("load",{timeout:5000}).then(()=>true,()=>false); await r.goto(B+"/requester"); ok("sign-in page in another tab ends the open visit",await gone); await c.close() }
for(const [n,i] of [["GPC",()=>Object.defineProperty(navigator,"globalPrivacyControl",{get:()=>true})],["DNT",()=>Object.defineProperty(navigator,"doNotTrack",{get:()=>"1"})]]){
  const {c,p,log}=await ctx(i); await p.goto(B+"/imprint"); await p.evaluate(()=>localStorage.setItem("builddoctor-analytics","yes")); await p.reload(); await p.waitForTimeout(1200)
  ok(n+": silent even with yes",log.an===0&&log.ph.length===0&&!(await box(p).isVisible())); await p.click("[data-analytics-do=open]"); ok(n+": explained",await p.getByText("so analytics stays off").isVisible()&&!(await p.locator("[data-analytics-do=accept]").isVisible())); await p.click("[data-analytics-do=close]"); ok(n+": closes, focus back",await p.evaluate(()=>document.activeElement.dataset.analyticsDo==="open")); await c.close() }
{ const {c,p}=await ctx(); await p.goto(B+"/imprint"); let again=false; p.on("load",()=>again=true); const r=await c.newPage(); await r.goto(B+"/requester"); await p.waitForTimeout(1500); ok("undecided tab loads again after the sign-in page",again); await c.close() }
{ const {c,p,log}=await ctx(); await p.goto(B.replace("localhost","127.0.0.1")+"/imprint").catch(()=>{}); await c.close() }
{ const {c,p,log}=await ctx(null,0); await p.goto(B+"/"); await p.click("[data-analytics-do=accept]"); await p.waitForTimeout(1500); await p.click("#place-3"); await p.waitForTimeout(800); ok("PostHog blocked: page works",await p.locator("#place-3").getAttribute("aria-pressed")==="true")
  await p.click("[data-analytics-do=open]"); await p.click("[data-analytics-do=decline]"); const n=log.ph.length; await p.waitForTimeout(6000); ok("no retry after withdrawal",log.ph.length===n,log.ph.length-n); ok("clear",ph(await stored(p)).length===0); await c.close() }
{ const {c,p,log}=await ctx(); await p.goto(B+"/requester"); await p.waitForTimeout(800); ok("sign-in page: no box, no choice",await box(p).count()===0&&!(await p.locator("[data-analytics-do=open]").first().isVisible().catch(()=>false))); await c.close() }
{ const {c,p,log}=await ctx(); await p.route("**/*",r=>r.continue()); await p.goto("http://127.0.0.1:4010/imprint"); await p.waitForTimeout(800); ok("other host name: not asked",!(await box(p).isVisible())&&!(await p.locator(".analytics-choice").first().isVisible())); await c.close() }
await browser.close(); console.log(bad?bad+" FAILED":"ALL OK"); process.exit(bad?1:0)
