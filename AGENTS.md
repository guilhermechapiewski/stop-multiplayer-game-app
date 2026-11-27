# Notes for coding agents

Stop: a free, open-source iPhone app (iOS 27+, iPhone only, portrait) for playing the "Stop" category word game
with friends in the same room over the local network (Bonjour, no router or internet required). Read `README.md`
for the overview and `CONTRIBUTING.md` for the full ground rules; this file is the short version.

## Hard rules

- **This repository is public.** Never commit personal data, a Team ID, certificates or provisioning profiles.
  Signing settings go in the git-ignored `Config/Local.xcconfig`.
- **Apple frameworks only.** No Swift packages, CocoaPods or SDKs; no analytics, ads, tracking or crash
  uploaders; no traffic beyond the local network.
- **Swift 6, complete strict concurrency, no warnings.** No `@unchecked Sendable` without a comment proving it
  is safe.
- **Test-first** with Swift Testing (`import Testing`, `@Test`, `#expect`). Logic lives in `StopKit`
  (`Packages/StopKit`) with unit tests; keep the app layer thin.
- **Every user-visible string** lives in `Localizable.xcstrings` in English and Brazilian Portuguese (pt-BR).
- **Every control has a VoiceOver label.**

## Build and test

```sh
tools/test.sh            # unit tests, then UI tests
tools/test.sh unit       # StopKit package tests + app unit tests (StopTests)
tools/test.sh ui         # app UI tests (StopUITests); extra args go to xcodebuild
```

## When behaviour changes

Update `README.md`, the files under `docs/` and `appstore/PUBLISHING.md` as needed, and say so in your summary.
