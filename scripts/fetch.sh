#!/bin/bash
# Downloads the filter lists into sources/. Each list is tried at its official
# URL first, then at a mirror where one is kept up to date. A list that can't
# be fetched, or is over a week old, is left out and build.sh keeps the last
# published copy of it instead, so one source being down doesn't stop the
# others from updating. Fails only if every list is missing.
set -uo pipefail

mkdir -p sources
fetched=0
# A list older than this is treated as a failed download, since mirrors can
# lag far behind.
MAX_AGE_DAYS=7
oldest=$(python3 -c "import datetime as d; print((d.datetime.now(d.timezone.utc) - d.timedelta(days=$MAX_AGE_DAYS)).strftime('%Y%m%d%H%M'))")

fetch() {
  local file=$1; shift
  for url in "$@"; do
    if ! curl -fsSL --retry 3 --retry-all-errors --connect-timeout 20 --max-time 120 -o "sources/$file.tmp" "$url" ||
      ! head -n 1 "sources/$file.tmp" | grep -q '^\[Adblock Plus'; then
      echo "::warning::$file: couldn't fetch a filter list from $url"
      continue
    fi
    local version
    version=$(grep -m 1 -i '^! Version:' "sources/$file.tmp" | tr -dc '0-9')
    # The cookie list has no version line, only the time it last changed
    # (`! Last modified: 2026-10-22 09:50 UTC`), which reads the same way.
    if [ -z "$version" ]; then
      version=$(grep -m 1 -i '^! Last modified:' "sources/$file.tmp" | tr -dc '0-9')
    fi
    if [ "${version:0:12}" \< "$oldest" ]; then
      echo "::warning::$file: the copy at $url is out of date (version ${version:-unknown})"
      continue
    fi
    mv "sources/$file.tmp" "sources/$file"
    echo "$file: fetched version $version from $url"
    fetched=$((fetched + 1))
    return
  done
  rm -f "sources/$file.tmp"
  echo "::warning::$file: every source failed; keeping the last published copy"
}

fetch easylist.txt \
  https://easylist.to/easylist/easylist.txt \
  https://easylist-downloads.adblockplus.org/easylist.txt
fetch easyprivacy.txt \
  https://easylist.to/easylist/easyprivacy.txt \
  https://easylist-downloads.adblockplus.org/easyprivacy.txt
# No mirror: the Adblock Plus copy of this one stopped updating in March 2024.
fetch easylist-cookie.txt \
  https://secure.fanboy.co.nz/fanboy-cookiemonster.txt
fetch fanboy-annoyance.txt \
  https://secure.fanboy.co.nz/fanboy-annoyance.txt \
  https://easylist.to/easylist/fanboy-annoyance.txt

if [ "$fetched" -eq 0 ]; then
  echo "::error::No filter list could be fetched."
  exit 1
fi
