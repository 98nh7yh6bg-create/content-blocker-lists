#!/bin/bash
# Keeps each published build as a GitHub Release, so any of the last few can
# be put live again with the workflow's "rollback_to" input.
set -euo pipefail

KEEP=5
version=$(python3 -c 'import json; print(json.load(open("dist/manifest.json"))["version"])')
summary=$(python3 - <<'PY'
import json
manifest = json.load(open("dist/manifest.json"))
print("\n".join("- {}: {:,} rules".format(l["source"], l["rules"]) for l in manifest["lists"]))
PY
)

gh release create "lists-$version" dist/manifest.json dist/manifest.sig dist/ads.json dist/privacy.json dist/cookies.json \
  --title "Lists $version" \
  --notes "$summary"

gh release list --limit 100 --json tagName --jq '.[].tagName' | { grep '^lists-' || true; } | sort -r | tail -n +$((KEEP + 1)) |
  while read -r old; do gh release delete "$old" --yes --cleanup-tag; done
