#!/bin/bash
# Converts the downloaded filter lists into WebKit content-blocker JSON and
# writes dist/manifest.json describing them.
#
# Generic element-hiding rules (`##selector` with no domain) are dropped:
# they apply thousands of selectors to every page, which slows styling and
# breaks more pages than it fixes. Network rules and site-specific hiding
# (`example.com##selector`) are kept.
set -euo pipefail

SAFARI_VERSION=26
MAX_RULES=150000
mkdir -p dist work

convert() {
  local name=$1 source=$2 title=$3 url=$4
  # Drop generic cosmetic rules, including ones that only exclude domains
  # (`~example.com##.ad`), and their generic exceptions.
  grep -v -E '^(##|#@#|#\?#|#\$#|#@\$#|#@\?#)|^~[^#]*#[@$?]*#' "sources/$source" > "work/$name.txt" || true

  ./ConverterTool convert \
    --safari-version "$SAFARI_VERSION" \
    --input-path "work/$name.txt" \
    --safari-rules-json-path "dist/$name.json" >/dev/null

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

python3 - "${CONVERTER_VERSION:-unknown}" <<'PY'
import datetime, json, sys
now = datetime.datetime.now(datetime.timezone.utc)
lists = [json.load(open(f"work/entries/{name}.json")) for name in ("ads", "privacy")]
manifest = {
    "format": 1,
    # Sortable, so the app only ever moves forward.
    "version": int(now.strftime("%Y%m%d%H%M")),
    "generated": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
    "converter": sys.argv[1],
    "license": "EasyList and EasyPrivacy, CC BY-SA 3.0 (https://easylist.to/)",
    "lists": lists,
}
json.dump(manifest, open("dist/manifest.json", "w"), indent=2)
print(f"manifest version {manifest['version']}")
PY
