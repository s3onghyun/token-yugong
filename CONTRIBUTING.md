# Contributing

Thanks for looking! Token Yugong is a small one-person project, so small, focused changes are the
easiest to review.

## Good first contributions

- **Translations.** The Japanese and Simplified Chinese texts (in the app and in `README.ja.md` /
  `README.zh-CN.md`) are AI-assisted. Every app string is one `L.t(en, ko, ja, zh)` call in
  `Sources/TokenPet/`; fix the wording and run `./test.sh` (it fails on a missing or wrong-script
  translation). The [translation issue template](.github/ISSUE_TEMPLATE/translation.yml) works too.
- **Bug reports** with your macOS version, Mac model, which AI tools you use, and what you expected.
  `swift run -c release TokenPet --scan-report` prints what the app read (no prompts or paths).
- **Docs**: typos, unclear install steps.

## Build and test

| Part | Where it builds | Test |
|---|---|---|
| macOS app (`Sources/`, `Tests/`, Swift) | macOS 13+ with Xcode or the Command Line Tools | `./test.sh`; `./scripts/bundle.sh` builds an ad-hoc signed `build/TokenYugong.app` (no Xcode project, no secrets) |
| Desktop beta (`desktop/`, Tauri 2) | Linux or Windows with Rust and Node.js | `cargo test --manifest-path desktop/core/Cargo.toml`; `npm ci --prefix desktop && npm run tauri --prefix desktop -- build` |
| Status-line bridge (`bridge/`) | any POSIX shell | covered by `./test.sh` |

CI runs `./test.sh` on macOS and builds the Linux and Windows bundles for every pull request. Local builds never
need signing secrets; only the release workflow signs and notarizes ([docs/release.md](docs/release.md)).

## Code

- `./test.sh` must pass.
- Every rule that turns numbers into the pet is in [LOGIC.md](LOGIC.md) and has a unit test; change
  both together.
- Keep the app local-only: no analytics, and no new network requests without an issue first.
- Keep the user-facing name **Token Yugong**. The `TokenPet` module, executable and settings domain stay
  as they are so existing settings, mountains and titles carry over.

## Art

The code is MIT. Grandpa Yugong and everything under `assets/` are not (see
[assets/LICENSE.md](assets/LICENSE.md)), so please don't send new art or modified sprites as a PR;
open an issue to discuss an idea instead.

## Pull requests

- One topic per pull request, with a line in `CHANGELOG.md` under `## Unreleased` (add the heading if it is missing) for anything users
  notice.
- Commit under an identity linked to your GitHub account (a noreply address is fine).
- The [pull request template](.github/pull_request_template.md) has the checklist. CI runs for a first-time contributor wait
  for the maintainer's approval, given after reading the diff.
- Security problems go through [SECURITY.md](SECURITY.md), not a public issue or PR.
- Everyone follows the [Code of Conduct](CODE_OF_CONDUCT.md).

Why CI and releases are set up the way they are: [docs/MAINTAINERS.md](docs/MAINTAINERS.md).

## AI-assisted contributions

Welcome, as long as you have read and tested what you submit. Mention material AI assistance in the pull request.
