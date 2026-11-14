import json, re, sys
page, cards_file = sys.argv[1], sys.argv[2]
s = open(page).read()
cards = json.load(open(cards_file))
stages = cards.get("stages", [])
new_cards = cards["cards"]
have = set(re.findall(r'\{ id: "([^"]+)"', s))
# stages
for st in stages:
    if f'id: "{st["id"]}"' not in s.split("const Q = [")[0]:
        entry = ",\n  " + "{ id: %s, name: %s, where: %s }" % (json.dumps(st["id"]), json.dumps(st["name"]), json.dumps(st["where"]))
        s = s.replace("\n];\n// look:", entry + "\n];\n// look:", 1)
out = []
for c in new_cards:
    if c["id"] in have:
        continue
    out.append("  { id: %s, stage: %s, area: %s, look: %s, log: %s, title: %s,\n    play: %s,\n    dflt: %s,\n    alt: %s }" % tuple(
        [json.dumps(c["id"]), json.dumps(c["stage"]), json.dumps(c["area"]), "true" if c["look"] else "false", json.dumps(c.get("log", "open")), json.dumps(c["title"]),
         json.dumps(c["play"]), json.dumps(c["dflt"]), json.dumps(c["alt"])]))
if out:
    marker = "\n];\nconst LOG_LABEL"
    assert marker in s
    s = s.replace(marker, ",\n\n" + ",\n".join(out) + marker, 1)
s = re.sub(r"// Source: docs/OPEN-QUESTIONS.md[^\n]*", "// Source: docs/OPEN-QUESTIONS.md, appended by the reviewer (last: " + cards.get("asof", "") + "). Two entries carry the number 32 in the log; they appear here as Q32a and Q32b.", s, 1)
open(page, "w").write(s)
print("added", len(out), "cards:", [c["id"] for c in new_cards if c["id"] not in have])
