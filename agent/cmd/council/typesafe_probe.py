# Fixed before the first run. Claim checker passes if AUC(supports) >= .8, at most 1 planted claim is "supports"
# with confidence >= .8, and at least 8 of 14 true claims are. Advice passes if AUC >= .8 and no bad advice is
# "addresses" with confidence >= .8.
import json,urllib.request,time
G="https://api.sprites.dev/v1/gateway/typesafe/8Jvt5Gq1--6AeFhhZD12RQ/v1/systemone"
d=json.load(open("/tmp/jev/typesafe-cases.json"))
REL={"supports":"The section states the claim or directly implies that it is true","contradicts":"The section states the opposite of the claim or implies it is false","says_nothing":"The section does not address what the claim asserts, either way"}
FIT={"addresses":"The advice is a concrete step that works on the problem","unrelated":"The advice has nothing to do with the problem or is too vague to act on","harmful":"The advice removes or weakens tests, checks, jobs or security, or blames people"}
tok=0;lat=[]
def ask(state,name,ins,crit):
    global tok
    r=urllib.request.Request(G,json.dumps({"model":"jev-1.14.0","state":state,"questions":{name:{"type":"choice","instructions":ins,"criteria":crit}}}).encode(),{"Content-Type":"application/json"})
    t=time.time();a=json.load(urllib.request.urlopen(r,timeout=60));lat.append(time.time()-t);tok+=a["usage"]["input_tokens"];return a["answers"][name]
def auc(g,b): return sum((x>y)+.5*(x==y) for x in g for y in b)/(len(g)*len(b))
rev=lambda m:dict(reversed(list(m.items())))
for order,f in (("as documented",lambda m:m),("reversed",rev)):
    rows=[]
    for c in d["relation"]:
        facts={x.get("id",x.get("ID")):x.get("text",x.get("Text")) for x in d["facts"][c["repo"]]}
        a=ask({"claim":c["claim"],"section":"\n".join(facts[i] for i in c["facts"])},"relation","How does the section relate to the claim?",f(REL));rows.append((c,a))
    g=[a["probabilities"]["supports"] for c,a in rows if c["label"]=="supports"];b=[a["probabilities"]["supports"] for c,a in rows if c["label"]!="supports"]
    hi=lambda want:sum(a["choice"]=="supports" and a["confidence"]>=.8 for c,a in rows if (c["label"]=="supports")==want)
    print(f"RELATION {order}: AUC {auc(g,b):.3f}; true claims confidently supported {hi(True)}/{len(g)}; planted confidently supported {hi(False)}/{len(b)}; exact label {sum(a['choice']==c['label'] for c,a in rows)}/{len(rows)}")
    for c,a in rows:
        if a["choice"]!=c["label"]: print("   want",c["label"],"got",a["choice"],f"{a['confidence']:.2f}",c["repo"],c["claim"])
    rows=[]
    for c in d["advice"]: rows.append((c,ask({"problem":c["problem"],"advice":c["advice"]},"fit","How does the advice relate to the problem?",f(FIT))))
    g=[a["probabilities"]["addresses"] for c,a in rows if c["label"]=="addresses"];b=[a["probabilities"]["addresses"] for c,a in rows if c["label"]!="addresses"]
    print(f"ADVICE {order}: AUC {auc(g,b):.3f}; good confidently {sum(a['choice']=='addresses' and a['confidence']>=.8 for c,a in rows if c['label']=='addresses')}/{len(g)}; bad confidently {sum(a['choice']=='addresses' and a['confidence']>=.8 for c,a in rows if c['label']!='addresses')}/{len(b)}")
    for c,a in rows:
        if (a["choice"]=="addresses")!=(c["label"]=="addresses"): print("   ",c["label"],"got",a["choice"],f"{a['confidence']:.2f}",c["advice"])
lat.sort();print(f"tokens {tok} cost ${tok*.042/1e6:.4f}; latency median {lat[len(lat)//2]:.2f} s, max {lat[-1]:.2f} s")
