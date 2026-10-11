#!/bin/bash
# Converts the downloaded filter lists into WebKit content-blocker JSON and
# writes dist/manifest.json describing them.
#
# For the ad and privacy lists, generic element-hiding rules (`##selector`
# with no domain) are dropped: they apply thousands of selectors to every
# page, which slows styling and breaks more pages than it fixes. Network rules
# and site-specific hiding (`example.com##selector`) are kept. The cookie list
# keeps its generic rules, since that's how it finds banners on any site.
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
  if [ ! -f "sources/$source" ]; then
    # fetch.sh couldn't download this list; keep the last published copy,
    # from the newest release archive.sh made. (The live site answers the
    # runners with 403, so it can't be read from here.)
    echo "$name: no fresh source, keeping the last published copy"
    local tag
    tag=$(gh release list --limit 100 --json tagName --jq '[.[].tagName | select(startswith("lists-"))] | sort | last // empty')
    if [ -n "$tag" ] && gh release download "$tag" --pattern "$name.json" --dir dist --clobber; then
      :
    elif [ -n "$optional" ]; then
      echo "::warning::$name: no fresh source and no published copy; leaving it out"
      return
    else
      echo "::error::$name: no fresh source and no published copy to keep"
      exit 1
    fi
  else
    convert_source "$name" "$source" "$generic"
  fi
  describe "$name" "$title" "$url"
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
  local name=$1 title=$2 url=$3
  python3 - "$name" "$title" "$url" "$MAX_RULES" <<'PY'
import hashlib, json, os, sys
name, title, url, max_rules = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
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
# rules are taken out, so the app's cookie switch still decides them. Without
# a fresh cookie list to take out, the annoyances copy isn't fresh either.
if [ -f sources/fanboy-annoyance.txt ] && [ -f sources/easylist-cookie.txt ]; then
  python3 - <<'PY2'
cookie = set(open("sources/easylist-cookie.txt", encoding="utf-8").read().splitlines())
with open("sources/fanboy-annoyance.txt", encoding="utf-8") as source, \
     open("sources/annoyances.txt", "w", encoding="utf-8") as out:
    kept = [line for line in source.read().splitlines() if line not in cookie or line.startswith("!")]
    out.write("\n".join(kept) + "\n")
print(f"annoyances: {len(kept)} lines after taking out the cookie list")
PY2
fi
convert annoyances annoyances.txt "Fanboy's Annoyance List" "https://easylist.to/" keep optional

python3 - "${CONVERTER_VERSION:-unknown}" <<'PY'
import datetime, json, os, sys
now = datetime.datetime.now(datetime.timezone.utc)
lists = [json.load(open(f"work/entries/{name}.json")) for name in ("ads", "privacy", "cookies")]
optional = [json.load(open(f"work/entries/{name}.json")) for name in ("annoyances",) if os.path.exists(f"work/entries/{name}.json")]
manifest = {
    "format": 1,
    # Identifies the build; rollbacks may put an older one live.
    "version": int(now.strftime("%Y%m%d%H%M")),
    # How often apps should check; can be raised later without an app update.
    "checkEveryHours": 24,
    "generated": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
    "converter": sys.argv[1],
    "license": "EasyList, EasyPrivacy and Fanboy's Annoyance List (CC BY-SA 3.0), EasyList Cookie List (CC BY 3.0); https://easylist.to/",
    "lists": lists,
    # Lists apps attach only when the user turns them on.
    "optionalLists": optional,
}
json.dump(manifest, open("dist/manifest.json", "w"), indent=2)
print(f"manifest version {manifest['version']}")
PY
