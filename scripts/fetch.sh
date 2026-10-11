#!/bin/bash
# Downloads the filter lists into sources/. Each list is tried at its official
# URL first, then at a mirror. A list that can't be fetched anywhere is left
# out, and build.sh keeps the live copy of it instead, so one source being down
# doesn't stop the others from updating. Fails only if every list is missing.
set -uo pipefail

mkdir -p sources
fetched=0

fetch() {
  local file=$1; shift
  for url in "$@"; do
    if curl -fsSL --retry 3 --retry-all-errors --connect-timeout 20 --max-time 120 -o "sources/$file.tmp" "$url" &&
      head -n 1 "sources/$file.tmp" | grep -q '^\[Adblock Plus'; then
      mv "sources/$file.tmp" "sources/$file"
      echo "$file: fetched from $url"
      fetched=$((fetched + 1))
      return
    fi
    echo "::warning::$file: couldn't fetch a filter list from $url"
  done
  rm -f "sources/$file.tmp"
  echo "::warning::$file: every source failed; keeping the live copy"
}

fetch easylist.txt \
  https://easylist.to/easylist/easylist.txt \
  https://easylist-downloads.adblockplus.org/easylist.txt
fetch easyprivacy.txt \
  https://easylist.to/easylist/easyprivacy.txt \
  https://easylist-downloads.adblockplus.org/easyprivacy.txt
fetch easylist-cookie.txt \
  https://secure.fanboy.co.nz/fanboy-cookiemonster.txt \
  https://easylist-downloads.adblockplus.org/fanboy-cookiemonster.txt

if [ "$fetched" -eq 0 ]; then
  echo "::error::No filter list could be fetched."
  exit 1
fi
