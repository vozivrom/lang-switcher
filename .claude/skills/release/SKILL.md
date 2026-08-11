---
name: release
description: Cut a LangSwitcher release — bump VERSION, write release notes, tag, and verify the published DMG. Use when asked to release, ship, or publish a new version.
---

# Releasing LangSwitcher

Pushing a `v*` tag builds and publishes. Everything below exists because some
step of it has gone wrong before.

## 1. Decide the version

`VERSION` at the repo root is the single source of truth — it's stamped into the
bundle and names the DMG, and the workflow **rejects a tag that disagrees with
it**. Bump the patch for fixes, the minor for anything a user would notice as
new.

## 2. Write the notes

Replace `RELEASE_NOTES.md` with what changed **in this release** — it isn't
cleared automatically, so stale contents would ship as the new notes.

Format: a `**New**` list and a `**Fixed**` list, omitting either if empty. No
install instructions; they live in the README. Describe what a user would
notice, not the implementation:

> - Words containing punctuation converted only partially in VS Code.

The workflow falls back to generating a list from commit subjects when the file
is empty, which is worse — commit subjects include repo housekeeping nobody
outside cares about.

## 3. Check, then ship

```sh
./Tests/run.sh          # must pass
./build.sh              # must build clean
```

```sh
git add -A && git commit          # short subject, no essay
git push origin development
git checkout main && git merge --ff-only development
git push origin main
git tag -a vX.Y.Z -m "LangSwitcher X.Y.Z" && git push origin vX.Y.Z
git checkout development
```

If pushing `main` is rejected, the remote is ahead because a pull request was
merged on GitHub. **Merge `origin/main` in and re-run the tests — never force.**

## 4. Verify what was published

A green checkmark is not enough: a skipped signing step used to read as success
and shipped two ad-hoc releases.

```sh
curl -s "https://api.github.com/repos/vozivrom/lang-switcher/actions/runs?per_page=1" \
  | python3 -c "import json,sys;print(json.load(sys.stdin)['workflow_runs'][0]['status'])"
```

Then confirm the DMG is signed with the certificate rather than ad-hoc. Mount it
at an explicit path — parsing `hdiutil` output breaks on the space in
`/Volumes/LangSwitcher 1` — and **detach it immediately**, because a mounted
volume is a second copy of the app and macOS then invalidates the Accessibility
grant:

```sh
curl -sL -o /tmp/rel.dmg "https://github.com/vozivrom/lang-switcher/releases/download/vX.Y.Z/LangSwitcher-X.Y.Z.dmg"
mkdir -p /tmp/lsverify && hdiutil attach /tmp/rel.dmg -nobrowse -readonly -mountpoint /tmp/lsverify
codesign -dvvv /tmp/lsverify/LangSwitcher.app 2>&1 | grep -E "Authority|Signature"
hdiutil detach /tmp/lsverify -quiet && rm -rf /tmp/rel.dmg /tmp/lsverify
```

`Authority=LangSwitcher Self-Signed` is correct. `Signature=adhoc` means the
`SIGNING_CERT_P12` secret didn't reach the workflow, and every user's
Accessibility permission will reset when they update — worth stopping for.

## Never do this

**Don't delete and re-push an existing tag to re-run a release.** GitHub turns
the release into a draft and its asset stops being downloadable. The workflow is
re-runnable, so use **Actions → Release → Run workflow**; if that isn't enough,
cut a new version.

## Afterwards

Suggest the user install it and confirm it works. Certificate-signed updates
keep the Accessibility grant, so a like-for-like update should need nothing
re-granted — if it does, something is wrong with the signing.
