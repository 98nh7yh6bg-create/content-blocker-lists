"""The parts of YouTube's data that Lens takes out: dist/youtube.json.

Reads uBlock Origin's and AdGuard's rules and keeps what Lens's cleaner
understands, for the site it runs on: the name of a part to take out, with no
conditions. Everything else is skipped. Only names, never code: Lens reads a
plain JSON array of them, and checks them again itself.

A name must end in an ad's part (`adPlacements`, `isAd`...), so a mistake
upstream can't take out a video's own details.

Fails when the rules that matter aren't found (their format has changed), so
build.sh keeps the last published copy.

Usage: youtube.py <rules> <our own names> <output>
"""
import json
import re
import sys

SITE = "m.youtube.com"
# Where a video's details sit on the page; `set` rules start with these.
PAGE_VARIABLES = {"ytInitialPlayerResponse", "playerResponse", "ytInitialReelWatchSequenceResponse"}
MUST_HAVE = {"adPlacements", "playerAds", "adSlots"}
MAX_LENGTH = 200

RULE = re.compile(r"([^#!\s\[][^#]*)##\+js\((.*)\)")
STEP = re.compile(r"[A-Za-z0-9_]+|\[\]|\[-\]")
# The word "ad" or "ads" in camelCase: not adaptiveFormats, address or shadow.
AD_WORD = re.compile(r"(?:^|[a-z0-9_])Ads?(?:[A-Z0-9_]|$)|^ads?(?:[A-Z0-9_]|$)")


def is_ad_part(path):
    """The same check as Lens's own (`YouTubeAds.isAdPart`)."""
    steps = path.split(".")
    return (
        len(path) <= MAX_LENGTH
        and all(STEP.fullmatch(step) for step in steps)
        and AD_WORD.search(steps[-1]) is not None
    )


def applies(domains):
    """Whether a rule's comma-separated domains include the site."""
    names = [name.strip() for name in domains.split(",")]
    def covers(name):
        return SITE == name or SITE.endswith("." + name)
    return any(covers(name) for name in names) and not any(
        name.startswith("~") and covers(name[1:]) for name in names
    )


def parts_in(line):
    """The names one rule asks to take out."""
    rule = RULE.fullmatch(line)
    if not rule or not applies(rule.group(1)):
        return set()
    name, *arguments = [piece.strip() for piece in re.split(r"(?<!\\),", rule.group(2))]
    if name in ("json-prune", "json-prune-fetch-response", "json-prune-xhr-response"):
        # A second argument means "only when this is there": not understood.
        if not arguments or (len(arguments) > 1 and arguments[1]):
            return set()
        return {path for path in arguments[0].split() if is_ad_part(path)}
    if name in ("set", "set-constant") and arguments[1:2] == ["undefined"]:
        variable, _, path = arguments[0].partition(".")
        return {path} if variable in PAGE_VARIABLES and is_ad_part(path) else set()
    return set()


def main(rules, own, output):
    with open(rules, encoding="utf-8") as lines:
        parts = set().union(*(parts_in(line.strip()) for line in lines))
    with open(own, encoding="utf-8") as lines:
        parts |= {name for name in (line.split("#")[0].strip() for line in lines) if name and is_ad_part(name)}
    missing = MUST_HAVE - parts
    if missing:
        sys.exit(f"::warning::youtube: {', '.join(sorted(missing))} not found; keeping the last published copy")
    with open(output, "w", encoding="utf-8") as file:
        json.dump(sorted(parts), file, separators=(",", ":"))
    print(f"youtube: {len(parts)} parts")


if __name__ == "__main__":
    main(*sys.argv[1:])
