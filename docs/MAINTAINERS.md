# Maintainer notes

Why releases and CI work the way they do. The step-by-step release procedure is in [release.md](release.md).

## The principle: a safe system makes contributions easy

Outside pull requests should be easy to accept. That is only possible when a pull request cannot reach anything that
matters: the signing certificate, the release, or users' machines. So the safety lives in the workflows, not in
trusting each contributor:

- `ci.yml` (Swift tests on macOS) and `desktop.yml` (desktop core tests and unsigned Linux/Windows bundles) run on
  `pull_request`, never `pull_request_target`, with `permissions: contents: read` and `persist-credentials: false`.
  A fork's run gets no secrets and a read-only token, so its code cannot sign, publish or push.
- `release.yml` never runs on pull requests: only on a `v*` tag push or a manual run by the maintainer.
- Workflow runs from first-time contributors wait for maintainer approval. Read the diff before approving, especially changes to `.github/`,
  `scripts/`, `bridge/`, `Package.swift` and `desktop/` build files.
- The default workflow token is read-only. Release jobs add only what they need: `id-token`/`attestations` for
  build provenance, and `contents: write` only in the final `release` job, which holds no Apple secrets.
- Every Action is pinned to a full commit SHA with the version in a comment. Dependabot proposes updates; review
  them like any other change to `.github/workflows/`.

## Releases: notarized or nothing

- Every macOS release is Developer ID signed, notarized by Apple and stapled. Without the signing secret (a fork),
  phase 1 only keeps an ad-hoc test archive for 7 days and phase 2 publishes nothing.
- Releases run in two phases. Phase 1 (tag push) tests, builds, signs and submits to Apple without waiting, and keeps
  the exact submitted zip and `submission.json` as an artifact for 90 days, next to the Linux beta assets. Phase 2
  (manual, `-f run_id=<phase-1 run>`) runs after Apple says `Accepted`: it checks the zip against the submission,
  staples that same app, verifies it (`stapler validate`, `spctl`), attests provenance and publishes.
- Apple can take hours. Do not re-run phase 1 to wait: each run builds and submits a new app, and a late `Accepted`
  then belongs to an app that no longer exists. Check the submission from a Mac and run phase 2 once it is accepted
  ([release.md](release.md#check-a-submission-from-a-mac)). While Apple is still working, phase 2 fails and changes
  nothing.
- Never move a tag that was already pushed; a rejected or broken release gets a new patch version.
- After publishing, bump the cask in [s3onghyun/homebrew-tap](https://github.com/s3onghyun/homebrew-tap) with the
  Release's `.sha256`.

## In-app updates verify before replacing

`Update.install` (`Sources/TokenPet/Update.swift`) replaces the app only after the downloaded zip (at most 50 MiB)
unzips to `TokenYugong.app` with the same bundle id and exactly the offered version, and passes
`codesign --verify --deep --strict`. A Developer ID signed copy (0.3.4 and later) also requires the new app to be signed
by the same **team ID** as the running app and to pass `spctl --assess` (notarized). Keep these checks when changing
the updater, and keep every release signed by the same team and notarized, or installed copies refuse the update.
An ad-hoc build you made yourself checks the signature only.

## Commits and identity

Commit under an identity linked to your GitHub account (a noreply address is fine), so authorship is clear. Never
commit secrets, signing material, `.env` files or local settings; secret names are listed in
[release.md](release.md#secrets), never their values. Contributors disclose material AI assistance in the pull request
([CONTRIBUTING.md](../CONTRIBUTING.md#ai-assisted-contributions)).
