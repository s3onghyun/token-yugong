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

## Code

- `./test.sh` must pass. No Xcode project needed: `./scripts/bundle.sh` builds the app.
- Every rule that turns numbers into the pet is in [LOGIC.md](LOGIC.md) and has a unit test; change
  both together.
- Keep the app local-only: no analytics, and no new network requests without an issue first.
- Keep the user-facing name **Token Yugong**. The `TokenPet` module, executable and settings domain stay
  as they are so existing settings, mountains and titles carry over.

## Art

The code is MIT. Grandpa Yugong and everything under `assets/` are not (see
[assets/LICENSE.md](assets/LICENSE.md)), so please don't send new art or modified sprites as a PR;
open an issue to discuss an idea instead.

## AI-assisted contributions

Welcome, as long as you have read and tested what you submit.
