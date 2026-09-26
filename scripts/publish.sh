#!/bin/bash
# Publishes dist/ as a new GitHub Release, but only when a list's contents
# changed since the latest release. Keeps the newest few releases.
set -euo pipefail

KEEP=5
fingerprint() { python3 -c 'import json,sys; print(" ".join(l["sha256"] for l in json.load(open(sys.argv[1]))["lists"]))' "$1"; }

current=$(fingerprint dist/manifest.json)
if gh release download --pattern manifest.json --dir work/previous --clobber 2>/dev/null; then
  previous=$(fingerprint work/previous/manifest.json)
  if [ "$current" = "$previous" ]; then
    echo "Lists unchanged; nothing to publish."
    exit 0
  fi
fi

version=$(python3 -c 'import json; print(json.load(open("dist/manifest.json"))["version"])')
tag="lists-$version"
summary=$(python3 - <<'PY'
import json
manifest = json.load(open("dist/manifest.json"))
print("\n".join("- {}: {:,} rules".format(l["source"], l["rules"]) for l in manifest["lists"]))
PY
)

gh release create "$tag" dist/manifest.json dist/manifest.sig dist/ads.json dist/privacy.json \
  --title "Lists $version" \
  --notes "$summary" \
  --latest

# Old releases aren't needed: the app always reads the latest one.
gh release list --limit 100 --json tagName --jq '.[].tagName' | { grep '^lists-' || true; } | sort -r | tail -n +$((KEEP + 1)) |
  while read -r old; do gh release delete "$old" --yes --cleanup-tag; done
