# Releasing (signing and notarization)

`.github/workflows/release.yml` makes a release in **two phases**. Apple's notarization queue for this team can take
hours. Waiting inside one job would mean every retry builds, signs and submits a new app, so a late `Accepted` has no
app left to staple. Instead phase 1 keeps the signed app it submitted, and phase 2 staples that same app and publishes
it once Apple is done. Nothing is ever published without notarization.

| Phase | When | What it does | Publishes |
|---|---|---|---|
| 1 (submit) | push of a `vX.Y.Z` tag, or a manual run with `-f tag=vX.Y.Z` | `macos`: test → universal build (`scripts/release-artifacts.sh`) → Developer ID signature → notarization submit, no waiting → keeps the signed zip, its `.sha256` and `submission.json` (submission id) as artifact `token-yugong-signed-X.Y.Z` for 90 days. `linux`: the Linux beta AppImage and `.deb` with their `.sha256` files and build provenance attestations, as `token-yugong-linux-beta-X.Y.Z` for 90 days | nothing |
| 2 (publish) | manual run with `-f run_id=<phase-1 run id>`, after Apple says `Accepted` | `notarized`: downloads the signed artifact → checks its sha256 → `notarytool info` → staples the same app → `stapler validate` and `spctl` → `TokenYugong-X.Y.Z-macos-universal.zip` and `.sha256` → build provenance attestation. `release`: GitHub Release with the mac zip, the Linux beta assets, their checksums and notes from `CHANGELOG.md` | Release |

While Apple is still `In Progress`, phase 2 fails and changes nothing; run the same command again later. The phase-1
artifacts last 90 days.

Without the signing secret (`APPLE_DEVELOPER_ID_P12`, e.g. in a fork), phase 1 still tests and builds the old ad-hoc
archive, keeps it 7 days as `token-yugong-adhoc-X.Y.Z` and says **Notarization skipped**. Phase 2 then finds no signed
artifact and publishes nothing.

## Commands (next patch: 0.3.8)

Prepare the release in a PR first, as for every patch: set `VERSION` to `0.3.8` and turn `## Unreleased` in
`CHANGELOG.md` into `## 0.3.8 (YYYY-MM-DD)`. Phase 1 checks that the tag is `v` + `VERSION`; phase 2 takes the release
notes from that changelog section and `.github/release-header.md`.

```sh
R=s3onghyun/token-yugong

# Phase 1 starts when the tag is pushed (annotated, on the merged release commit of main)
git fetch origin main && git tag -a v0.3.8 -m "Token Yugong v0.3.8" origin/main && git push origin v0.3.8

# The phase-1 run id. Its summary shows the submission id and the exact phase-2 command
gh run list -R "$R" -w release.yml -L 5
gh run view <run id> -R "$R" --log | grep -E 'Notarization (submitted|skipped)'

# When Apple says Accepted (see "Check a submission from a Mac"), phase 2
gh workflow run release.yml -R "$R" --ref main -f run_id=<phase-1 run id>
gh run list -R "$R" -w release.yml -L 1

# After it is published: check the downloaded asset on a Mac
gh release download v0.3.8 -R "$R" -p 'TokenYugong-0.3.8-macos-universal.zip*'
shasum -a 256 -c TokenYugong-0.3.8-macos-universal.zip.sha256
ditto -x -k TokenYugong-0.3.8-macos-universal.zip . && spctl -a -vv -t exec TokenYugong.app   # source=Notarized Developer ID
gh attestation verify TokenYugong-0.3.8-macos-universal.zip -R "$R"
```

Always run phase 2 with `--ref main` (the phase-2 jobs live in the default branch's workflow), and only after the whole
phase-1 run (`macos` and `linux`) has finished successfully.

Then bump `Casks/token-yugong.rb` in [s3onghyun/homebrew-tap](https://github.com/s3onghyun/homebrew-tap): `version`
and `sha256` (the hash in the Release's `TokenYugong-X.Y.Z-macos-universal.zip.sha256`).

| Phase 2 result | Meaning | What to do |
|---|---|---|
| success, summary `Published vX.Y.Z` | the Release exists | bump the cask |
| failure, annotation `Notarization still in progress` | Apple is still working; nothing was published or changed | the same command later (or Re-run that phase-2 run) |
| failure, `Notarization Invalid` and the notarization log (JSON) | Apple rejected it | fix the log's `issues`, then a new patch version from phase 1 |
| failure, `The signed zip does not match submission.json` | the artifact is not what phase 1 left | do not publish; find out why, then phase 1 again (below) |
| failure, `Tag vX.Y.Z is at …, but phase 1 built …` | the tag moved after phase 1 | move it back, or phase 1 again for that tag |
| failure, `Run … must be a finished, successful release.yml run` or `needs exactly one token-yugong-signed-X.Y.Z artifact` | wrong run id, phase 1 failed or ran without signing, or 90 days passed | check the run id; otherwise phase 1 again |
| failure, `release … already exists` | already published | nothing |

`-f submission_id=<id>` asks about another submission instead of the one in the artifact. Stapling finds the ticket by
the app's code hash, not by the submission id, so this only works when the same app was accepted under that other
submission; otherwise `stapler`/`spctl` fail and nothing is published.

### Phase 1 again for an existing tag

Re-running a tag-push run on GitHub runs the old workflow inside that tag. To redo phase 1 for an existing tag, run
the default branch's workflow with the `tag` input. The source comes from the tag, the notarization script from the
workflow's commit.

```sh
gh workflow run release.yml -R "$R" --ref main -f tag=vX.Y.Z
```

The result is the same as a tag push (90-day artifacts, Linux included, nothing published). It signs and submits a new
app, so use this run's id for phase 2 and wait for its submission.

## What `scripts/notarize-app.sh` does

`submit` (phase 1, all signing secrets):

1. Creates a keychain for this run only and imports the `.p12` into it (the runner's login keychain is not used). A
   trap deletes it on exit.
2. Re-signs `build/TokenYugong.app` (ad-hoc from `scripts/bundle.sh`) with the Developer ID Application certificate of
   `APPLE_TEAM_ID`: `codesign --force --options runtime --timestamp`. Hardened runtime and a secure timestamp are what
   notarization requires. The signing identifier stays the bundle id `dev.yugongpet.app`. No entitlements are needed:
   the app only reads files and runs system tools (`ditto`, `codesign`, `spctl`, `/bin/sh`) as separate processes.
3. Zips the signed app to `dist/notary/TokenYugong-X.Y.Z-macos-universal-signed.zip` with a `.sha256` and submits that
   exact zip with `xcrun notarytool submit` (no `--wait`).
4. Writes the submission id, version, zip name, zip sha256, built commit and time to `dist/notary/submission.json` and
   prints `Notarization submitted: <id>`.

`finish [<submission id>]` (phase 2; no `.p12`, only the team ID and notarization auth):

1. Checks the zip in `dist/notary/` against `submission.json` and its `.sha256`.
2. `xcrun notarytool info <id>` (a transient failure is retried three times). `In Progress` → exit 75; anything else but
   `Accepted` → prints `notarytool log` (only for an id that passed the UUID check) and exits 1.
3. `Accepted` → unzips to `build/TokenYugong.app`, checks the signing team, `xcrun stapler staple` → `stapler validate`
   → `codesign --verify --deep --strict` → `spctl --assess` must say `source=Notarized Developer ID`.
4. From the stapled app, makes `dist/TokenYugong-X.Y.Z-macos-universal.zip` and `.sha256` exactly as
   `scripts/release-artifacts.sh` does: the in-app update and the Homebrew cask download that name.

Secrets reach each step only as environment variables and are never printed (notarytool's error output is redacted
before it is shown). The `.p12` is only in phase 1's signing step. Only the final `release` job can write to the repository
(`contents: write`), and it holds no Apple secrets. The release workflow never runs on pull requests.

Local builds (`./scripts/bundle.sh`, `./scripts/release-artifacts.sh`) stay ad-hoc signed and need no secrets.

## Secrets

Settings → Secrets and variables → Actions → Repository secrets. Only the names are written here.

| Name | Required | Content |
|---|---|---|
| `APPLE_DEVELOPER_ID_P12` | yes (the switch) | base64 of the `.p12` with the Developer ID Application certificate and its private key |
| `APPLE_DEVELOPER_ID_P12_PASSWORD` | yes | the password the `.p12` was exported with |
| `APPLE_TEAM_ID` | yes | team ID (10 uppercase letters/digits) |
| `APPLE_API_KEY_ID` | notarization auth A (used here) | App Store Connect API key ID |
| `APPLE_API_ISSUER_ID` | notarization auth A | that key's issuer ID |
| `APPLE_API_KEY_P8` | notarization auth A | base64 of `AuthKey_<key id>.p8` |
| `APPLE_ID` | notarization auth B | Apple account email |
| `APPLE_APP_SPECIFIC_PASSWORD` | notarization auth B | an app-specific password for that account |

Set A or B. If any A value is present, A is used. To set one without it landing in shell history:
`base64 -i AuthKey_XXXXXXXXXX.p8 | gh secret set APPLE_API_KEY_P8 -R s3onghyun/token-yugong`, and
`gh secret set APPLE_TEAM_ID -R s3onghyun/token-yugong` (prompts for the value).

## Check a submission from a Mac

The phase-1 summary and log (`Notarization submitted: <id>`) carry the submission id. With the API key, kept outside
the repository:

```sh
xcrun notarytool info <id> --key ~/keys/AuthKey_XXXXXXXXXX.p8 --key-id <key id> --issuer <issuer id>
xcrun notarytool log  <id> --key ~/keys/AuthKey_XXXXXXXXXX.p8 --key-id <key id> --issuer <issuer id>   # details once done
xcrun notarytool history  --key ~/keys/AuthKey_XXXXXXXXXX.p8 --key-id <key id> --issuer <issuer id>   # recent submissions
```

`xcrun notarytool store-credentials token-yugong --key … --key-id … --issuer …` once, then
`xcrun notarytool info <id> --keychain-profile token-yugong`. Checking every few hours is enough.

An `Invalid` submission's `notarytool log` lists the reasons in `issues` (signature, hardened runtime and timestamp
problems are the usual ones). Fix them and tag a new patch version; never move a tag that was already pushed.

## Notes on the first notarized release (0.3.3)

- The in-app update from 0.3.2 and older works: those versions accept a new app with the same bundle id, the offered
  version and a valid signature (`Update.install`), without pinning a signing team. Homebrew users get it with `brew upgrade`.
- From 0.3.4 a Developer ID signed copy pins its own team: `Update.install` also requires the new app to satisfy
  `anchor apple generic and certificate leaf[subject.OU] = "<the running app's TeamIdentifier>"` and to pass
  `spctl --assess --type execute` (notarized). An ad-hoc build (no team) still checks the signature only. Every
  release must therefore stay signed by the same team and notarized, or the in-app update refuses it.
- The tap's cask caveat about "ad-hoc signed and not notarized" goes away with the 0.3.3 cask bump; the caveat about
  the `statusLine` entry stays.
- A Developer ID certificate is valid for five years. Thanks to the secure timestamp, published releases keep opening
  after it expires. On renewal, replace only `APPLE_DEVELOPER_ID_P12` and its password.
