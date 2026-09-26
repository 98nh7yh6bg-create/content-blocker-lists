# content-blocker-lists

Daily WebKit content-blocker lists built from
[EasyList and EasyPrivacy](https://easylist.to/), for a WebKit browser app.

A daily GitHub Action downloads the filter lists, adds our own fixes from
`unbreak.txt`, converts them with AdGuard's
[SafariConverterLib](https://github.com/AdguardTeam/SafariConverterLib)
(built from source at a pinned tag and commit), runs sanity checks, and publishes to GitHub
Pages only when the lists change. Each published build is also kept as a
release (the newest 5).

## Files

- `ads.json` – EasyList as WebKit content-blocker JSON
- `privacy.json` – EasyPrivacy as WebKit content-blocker JSON
- `manifest.json` – version, and each list's SHA-256, size and rule count
- `manifest.sig` – Ed25519 signature of `manifest.json`

Served at `https://lists.angelakismax.com/<file>` (GitHub Pages).

Apps should verify `manifest.sig` against their built-in public key, then each
list's SHA-256 against the manifest, before using anything.

## When a site breaks

Add an exception to `unbreak.txt` and push; it goes live on the next run (run
the workflow by hand to publish right away).

## Safety checks

A build isn't published if a list's rule count moves more than 20% from the live
version, or if any rule would block the main page of a major site. Run the
workflow with **force** to publish anyway after checking.

To undo a bad build, run the workflow with **rollback_to** set to an earlier
release tag (e.g. `lists-202609270417`); that build goes live again.

## What's included

Network blocking rules and site-specific element hiding. Generic element-hiding
rules (`##selector` with no domain) are left out: they apply thousands of
selectors to every page, which slows pages down and breaks more than it fixes.

## Signing

`scripts/keygen.swift` makes a key pair. The private key is stored only in the
`SIGNING_KEY` Actions secret; the public key is built into the app. Replacing the
key requires an app update with the new public key.

## License

The lists are derived from EasyList and EasyPrivacy and are available under the
same terms: [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/)
(EasyList is dual licensed with GPLv3). The build scripts are MIT licensed.
