# Monetization plan (open core)

The app stays open source so people can see the taste behind it; money comes from
convenience and characters, never from locking the core meters.

## Free (this repo, MIT code)

- Build it yourself with `swift build`.
- One default character (CC BY-NC-ND once final).
- Claude 5-hour and weekly meters, Codex meters, all four pet states, screen-share hiding.

## Paid options

| Option | Price idea | What the buyer gets | Precedent |
|---|---|---|---|
| Notarized convenience build | $2.99 one-time | Signed, notarized DMG and auto-update; no Xcode needed | Maccy (free source, paid App Store build) |
| Mac App Store build | $2.99 | Same, through the store | Maccy, Ice-style utilities |
| Character packs | $0.99-$1.99 each, or a $4.99 bundle | New characters and seasonal skins as data files dropped into the app | Sticker and theme packs |
| Pro features | Inside the $2.99 build or $0.99 add-on | Usage history chart, notifications before the limit, multiple accounts, desktop widget | CodexBar's widget and multi-provider features (free there, so keep Pro light) |

## Constraints to respect

- The Mac App Store sandbox cannot read `~/.claude` or `~/.codex` without the user picking
  the folder (security-scoped bookmark). The notarized DMG avoids that friction; ship that
  first.
- Premium character files never go into the public repo.
- Never sell access to the usage numbers themselves: competitors give them away (see the
  competitor table in the report).
