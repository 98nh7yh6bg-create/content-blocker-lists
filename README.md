# content-blocker-lists

Daily WebKit content-blocker lists built from
[EasyList and EasyPrivacy](https://easylist.to/), for a WebKit browser app.

A GitHub Action downloads the filter lists, converts them with AdGuard's
[SafariConverterLib](https://github.com/AdguardTeam/SafariConverterLib)
(pinned by version and checksum), and publishes a new release only when the
lists change.

## Files (in each release)

- `ads.json` – EasyList as WebKit content-blocker JSON
- `privacy.json` – EasyPrivacy as WebKit content-blocker JSON
- `manifest.json` – version, and each list's SHA-256, size and rule count
- `manifest.sig` – Ed25519 signature of `manifest.json`

The newest release is always at
`https://github.com/<owner>/content-blocker-lists/releases/latest/download/<file>`.

Apps should verify `manifest.sig` against their built-in public key, then each
list's SHA-256 against the manifest, before using anything.

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
