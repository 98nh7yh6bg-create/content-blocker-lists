#!/bin/bash
# Converts the downloaded filter lists into WebKit content-blocker JSON and
# writes dist/manifest.json describing them.
#
# For the ad and privacy lists, generic element-hiding rules (`##selector`
# with no domain) are dropped: they apply thousands of selectors to every
# page, which slows styling and breaks more pages than it fixes. Network rules
# and site-specific hiding (`example.com##selector`) are kept. The cookie list
# keeps its generic rules, since that's how it finds banners on any site, but
# only on the main page (see `convert_source`).
#
# Optional lists (only annoyances so far) go under `optionalLists` in the
# manifest. Apps that predate them only read `lists`, so they don't pick up
# lists they have no switch for.
set -euo pipefail

SAFARI_VERSION=26
MAX_RULES=150000
mkdir -p dist work

convert() {
  local name=$1 source=$2 title=$3 url=$4 generic=${5:-drop} optional=${6:-}
  local version=""
  if [ ! -f "sources/$source" ]; then
    # fetch.sh couldn't download this list; keep the last published copy,
    # from the newest release archive.sh made. (The live site answers the
    # runners with 403, so it can't be read from here.)
    echo "$name: no fresh source, keeping the last published copy"
    local tag
    tag=$(gh release list --limit 100 --json tagName --jq '[.[].tagName | select(startswith("lists-"))] | sort | last // empty')
    if [ -n "$tag" ] && gh release download "$tag" --pattern "$name.json" --dir dist --clobber; then
      # The kept copy's source is as old as that release says (manifests
      # from before `sourceVersion` only give the build's own time).
      version=$(gh release download "$tag" --pattern manifest.json --output - | python3 -c '
import json, sys
manifest = json.load(sys.stdin)
entry = next((e for e in manifest["lists"] + manifest.get("optionalLists", []) if e["name"] == sys.argv[1]), {})
print(entry.get("sourceVersion") or manifest["version"])' "$name") || version=""
      echo "$name" >> work/kept.txt
    elif [ -n "$optional" ]; then
      echo "::warning::$name: no fresh source and no published copy; leaving it out"
      return
    else
      echo "::error::$name: no fresh source and no published copy to keep"
      exit 1
    fi
  else
    convert_source "$name" "$source" "$generic"
    version=$(cat "sources/$source.version" 2>/dev/null || true)
  fi
  # Also on a kept copy, so the change reaches lists whose source is down.
  if [ "$generic" = keep ]; then main_page_only "$name"; fi
  describe "$name" "$title" "$url" "$version"
}

# Site-wide hiding rules apply to the main page only. Checked in every frame
# too, their thousands of selectors cost each embedded ad, video and comment
# box some styling time (about 5% in Speedometer, which runs its tests in
# frames), while banners almost always sit on the main page.
main_page_only() {
  python3 - "dist/$1.json" <<'PY'
import json, sys
path = sys.argv[1]
rules = json.load(open(path))
scoped = 0
for rule in rules:
    trigger = rule["trigger"]
    if rule["action"]["type"] == "css-display-none" and not any(
        key in trigger for key in ("if-domain", "if-top-url", "if-frame-url", "load-context")
    ):
        trigger["load-context"] = ["top-frame"]
        scoped += 1
json.dump(rules, open(path, "w"), separators=(",", ":"))
print(f"{path}: {scoped} site-wide hiding rules on the main page only")
PY
}

convert_source() {
  local name=$1 source=$2 generic=$3
  if [ "$generic" = keep ]; then
    cp "sources/$source" "work/$name.txt"
  else
    # Drop generic cosmetic rules, including ones that only exclude domains
    # (`~example.com##.ad`), and their generic exceptions.
    grep -v -E '^(##|#@#|#\?#|#\$#|#@\$#|#@\?#)|^~[^#]*#[@$?]*#' "sources/$source" > "work/$name.txt" || true
  fi
  # Our own fixes go last, so their exceptions override the list's rules.
  # (WebKit only applies exceptions within the same list, so each gets a copy.)
  printf '\n' >> "work/$name.txt"
  cat unbreak.txt >> "work/$name.txt"

  "${CONVERTER:-./ConverterTool}" convert \
    --safari-version "$SAFARI_VERSION" \
    --input-path "work/$name.txt" \
    --safari-rules-json-path "dist/$name.json" >/dev/null
}

describe() {
  local name=$1 title=$2 url=$3 version=${4:-}
  python3 - "$name" "$title" "$url" "$MAX_RULES" "$version" <<'PY'
import hashlib, json, os, sys
name, title, url, max_rules, version = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), sys.argv[5]
path = f"dist/{name}.json"
data = open(path, "rb").read()
rules = json.loads(data)
if not isinstance(rules, list) or not rules:
    sys.exit(f"{name}: converter produced no rules")
if len(rules) > max_rules:
    sys.exit(f"{name}: {len(rules)} rules is over WebKit's limit of {max_rules}")
entry = {
    "name": name,
    "file": f"{name}.json",
    "sha256": hashlib.sha256(data).hexdigest(),
    "bytes": len(data),
    "rules": len(rules),
    "source": title,
    "sourceURL": url,
}
if version:
    # When the filter list itself was last updated (YYYYMMDDHHMM).
    entry["sourceVersion"] = int(version[:12])
os.makedirs("work/entries", exist_ok=True)
json.dump(entry, open(f"work/entries/{name}.json", "w"))
print(f"{name}: {len(rules)} rules, {len(data)} bytes")
PY
}

convert ads easylist.txt "EasyList" "https://easylist.to/"
convert privacy easyprivacy.txt "EasyPrivacy" "https://easylist.to/"
convert cookies easylist-cookie.txt "EasyList Cookie List" "https://easylist.to/" keep

# Fanboy's Annoyance List (newsletter and "open in app" pop-ups, chat and
# notification prompts, social widgets) also bundles the cookie list. Those
# sections are taken out, so the app's cookie switch still decides them. Each
# bundled file starts with a line naming it (`! easylist_cookie_general_hide.txt`,
# or `! *** easylist:easylist_cookie/general_hide.txt ***` before October
# 2026); if none of them name the cookie list, the format changed and the
# list is left out (keeping the last published copy) rather than published
# with cookie rules.
if [ -f sources/fanboy-annoyance.txt ]; then
  python3 - <<'PY2' || rm -f sources/annoyances.txt
import re, sys
marker = re.compile(r"^! (?:\*\*\* (\S+) \*\*\*|([\w./-]+\.txt))$")
kept, skipping, removed, dropped = [], False, 0, 0
for line in open("sources/fanboy-annoyance.txt", encoding="utf-8").read().splitlines():
    match = marker.match(line)
    if match:
        skipping = "easylist_cookie" in (match.group(1) or match.group(2))
        removed += skipping
    if skipping:
        dropped += 1
    else:
        kept.append(line)
if not removed:
    sys.exit("::warning::annoyances: couldn't find the bundled cookie list sections; leaving it out")
open("sources/annoyances.txt", "w", encoding="utf-8").write("\n".join(kept) + "\n")
print(f"annoyances: took out {removed} cookie list sections ({dropped} lines), kept {len(kept)} lines")
PY2
  if [ -f sources/annoyances.txt ]; then cp sources/fanboy-annoyance.txt.version sources/annoyances.txt.version; fi
fi
convert annoyances annoyances.txt "Fanboy's Annoyance List" "https://easylist.to/" keep optional

# HaGeZi's Pop-Up Ads: the ad networks behind pop-ups, pop-unders and fake
# "I'm not a robot" boxes on streaming and download sites. They change
# address faster than EasyList follows; this list keeps up. It's only
# domains, which cost almost nothing per request. Those EasyList already
# blocks are left out, to keep it light. Apps download it and don't bundle it.
if [ -f sources/hagezi-popupads.txt ]; then
  python3 - <<'PY'
import os
easylist = set()
if os.path.exists("sources/easylist.txt"):
    easylist = {line.strip() for line in open("sources/easylist.txt", encoding="utf-8") if line.startswith("||")}
lines = open("sources/hagezi-popupads.txt", encoding="utf-8").read().splitlines()
domains = [line for line in lines if line.startswith("||")]
kept = [line for line in domains if line not in easylist]
open("sources/popups.txt", "w", encoding="utf-8").write("\n".join([lines[0]] + kept) + "\n")
print(f"popups: {len(kept)} of {len(domains)} domains, the rest already in EasyList")
PY
  cp sources/hagezi-popupads.txt.version sources/popups.txt.version
fi
convert popups popups.txt "HaGeZi's Pop-Up Ads" "https://github.com/hagezi/dns-blocklists"

python3 - "${CONVERTER_VERSION:-unknown}" <<'PY'
import datetime, json, os, sys
now = datetime.datetime.now(datetime.timezone.utc)
lists = [json.load(open(f"work/entries/{name}.json")) for name in ("ads", "privacy", "cookies", "popups")]
optional = [json.load(open(f"work/entries/{name}.json")) for name in ("annoyances",) if os.path.exists(f"work/entries/{name}.json")]
manifest = {
    "format": 1,
    # Identifies the build; rollbacks may put an older one live.
    "version": int(now.strftime("%Y%m%d%H%M")),
    # How often apps should check; can be raised later without an app update.
    "checkEveryHours": 24,
    "generated": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
    "converter": sys.argv[1],
    "license": "EasyList, EasyPrivacy and Fanboy's Annoyance List (CC BY-SA 3.0), EasyList Cookie List (CC BY 3.0); https://easylist.to/. HaGeZi's Pop-Up Ads (GPL-3.0); https://github.com/hagezi/dns-blocklists",
    "lists": lists,
    # Lists apps attach only when the user turns them on.
    "optionalLists": optional,
}
json.dump(manifest, open("dist/manifest.json", "w"), indent=2)
print(f"manifest version {manifest['version']}")
PY

# Lists kept from an earlier build whose source is 3 days old or more: their
# download has been failing for about that long. They're still published as
# they are; the workflow fails afterwards, so GitHub emails about it.
python3 - <<'PY'
import datetime, json, os
limit = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=int(os.environ.get("STALE_AFTER_DAYS", "3")))
manifest = json.load(open("dist/manifest.json"))
kept = set(open("work/kept.txt").read().split()) if os.path.exists("work/kept.txt") else set()
stale = []
for entry in manifest["lists"] + manifest.get("optionalLists", []):
    version = str(entry.get("sourceVersion") or "")
    if entry["name"] in kept and version:
        updated = datetime.datetime.strptime(version[:12], "%Y%m%d%H%M").replace(tzinfo=datetime.timezone.utc)
        if updated < limit:
            stale.append(f"{entry['name']} (last updated {updated:%d %b})")
open("work/stale.txt", "w").write(", ".join(stale))
if stale:
    print("::warning::Not updated for 3 days or more: " + ", ".join(stale))
PY
