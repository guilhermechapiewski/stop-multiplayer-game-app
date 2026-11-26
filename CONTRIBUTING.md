# Contributing

Thanks for helping improve Stop. Bug reports, ideas and pull requests are all welcome.

## How the project works

The maintainer publishes the app on the App Store, reviews every pull request, and decides what goes into each
release. You don't need an Apple Developer account or signing setup to contribute: the simulator covers most
work, and two or more devices help for multiplayer changes. See "Building" in the [README](README.md).

## Ground rules

- **Privacy first.** The app collects no data and only talks to other devices on the local network. Pull
  requests that add analytics, advertising, tracking, crash uploaders or any traffic beyond the local network
  will not be accepted.
- **No third-party dependencies.** Apple frameworks only: no Swift packages, CocoaPods or SDKs.
- **Swift 6 with complete strict concurrency.** No warnings. Do not use `@unchecked Sendable` without a
  comment proving it is safe.
- **Localization and accessibility.** Every user-visible string is in `Localizable.xcstrings` in English and
  Brazilian Portuguese (pt-BR), and every control has a VoiceOver label.

## Never commit personal data

This is a public repository. Do not commit, paste into issues, or include in test fixtures your Team ID,
certificates, provisioning profiles, real names, or network details (IP addresses, Wi-Fi names). Signing
settings belong in the git-ignored `Config/Local.xcconfig`.

## Workflow

1. Fork, then create a branch from `main`.
2. Work test-first: write a failing test, watch it fail for the expected reason, make it pass, then tidy up.
   Use Swift Testing (`import Testing`, `@Test`, `#expect`). Put logic in `StopKit` with unit tests; keep the
   app layer thin.
3. Run all tests (below) and make sure the output is clean.
4. Test multi-device changes with `docs/device-test-checklist.md`.
5. If user-facing features or requirements changed, update the README and say so in the pull request.
6. Open a pull request describing what changed, why, and how you tested it.

## Running tests

```sh
tools/test.sh            # everything
tools/test.sh package    # swift test --package-path Packages/StopKit
tools/test.sh app        # xcodebuild test on an iPhone simulator
```

## Style

Follow the existing code: small types, clear names, `os.Logger` for logging, and every user-visible string
ready for localization. Every button either works or tells the user why not.

By contributing you agree that your contributions are licensed under the MIT license.
