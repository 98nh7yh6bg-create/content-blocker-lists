"""Stops a bad build before it reaches anyone.

Sets PUBLISH=true in $GITHUB_ENV when the lists changed and look sane.
Fails the job when they don't, unless FORCE is set:

- a list's rule count moved more than 20% since the live version, or
- a rule would block the main page of a major site.
"""
import json
import os
import re
import sys
import urllib.request

LIVE_URL = os.environ.get("LIVE_URL", "")
FORCE = bool(os.environ.get("FORCE"))
MAX_CHANGE = 0.20

# Sites that must always load. A rule that blocks one of these pages outright
# is almost certainly a mistake upstream.
MUST_LOAD = [
    "https://www.google.com/",
    "https://www.apple.com/",
    "https://www.youtube.com/",
    "https://en.wikipedia.org/wiki/Main_Page",
    "https://github.com/",
    "https://www.amazon.com/",
    "https://www.reddit.com/",
    "https://www.bbc.com/",
    "https://x.com/",
    "https://www.instagram.com/",
]


def export(name, value):
    path = os.environ.get("GITHUB_ENV")
    if path:
        with open(path, "a") as env:
            env.write(f"{name}={value}\n")


def live_manifest():
    if not LIVE_URL:
        return None
    try:
        with urllib.request.urlopen(f"{LIVE_URL}/manifest.json", timeout=20) as response:
            return json.load(response)
    except Exception as error:  # First run, or the site is unreachable.
        print(f"No live manifest ({error}); skipping comparisons.")
        return None


def blocks_main_page(rule):
    """Whether a rule blocks a top-level page of a MUST_LOAD site."""
    action, trigger = rule.get("action", {}), rule.get("trigger", {})
    if action.get("type") != "block":
        return None
    types = trigger.get("resource-type")
    if types and "document" not in types:
        return None
    if trigger.get("load-type") == ["third-party"]:
        return None
    if any(key in trigger for key in ("if-domain", "if-top-url", "if-frame-url")):
        return None
    flags = 0 if trigger.get("url-filter-is-case-sensitive") else re.IGNORECASE
    try:
        pattern = re.compile(trigger.get("url-filter", ""), flags)
    except re.error:
        return None
    unless = trigger.get("unless-domain", [])
    for url in MUST_LOAD:
        host = url.split("/")[2]
        if any(host == d.lstrip("*") or host.endswith("." + d.lstrip("*.")) for d in unless):
            continue
        if pattern.search(url):
            return url
    return None


def main():
    manifest = json.load(open("dist/manifest.json"))
    previous = live_manifest()
    problems = []

    if previous:
        before = {entry["name"]: entry for entry in previous.get("lists", [])}
        if [e["sha256"] for e in manifest["lists"]] == [before.get(e["name"], {}).get("sha256") for e in manifest["lists"]]:
            print("Lists unchanged; nothing to publish.")
            return
        for entry in manifest["lists"]:
            old = before.get(entry["name"])
            if not old or not old.get("rules"):
                continue
            change = abs(entry["rules"] - old["rules"]) / old["rules"]
            print(f"{entry['name']}: {old['rules']} -> {entry['rules']} rules ({change:+.1%})")
            if change > MAX_CHANGE:
                problems.append(f"{entry['name']} changed by {change:.0%} ({old['rules']} -> {entry['rules']})")

    for entry in manifest["lists"]:
        rules = json.load(open(f"dist/{entry['file']}"))
        for rule in rules:
            url = blocks_main_page(rule)
            if url:
                problems.append(f"{entry['name']} blocks {url}: {json.dumps(rule['trigger'])}")
                break

    if problems:
        print("Sanity checks failed:\n- " + "\n- ".join(problems))
        if not FORCE:
            sys.exit(1)
        print("FORCE is set; publishing anyway.")

    export("PUBLISH", "true")


if __name__ == "__main__":
    main()
