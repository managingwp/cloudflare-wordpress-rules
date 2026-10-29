---
title: Release notifications
description: How to be told when a new repository release ships.
---

# Release notifications

A repository release is cut by folding everything since the previous release into
one `Release X.Y.Z` commit and tagging it with the same number. That tag **is**
the release — there is no separate publish step, so whatever reads tags sees a
release the moment it is pushed.

## Subscribe to the release feed

```text
https://github.com/managingwp/cloudflare-wordpress-rules/releases.atom
```

Paste that URL into any feed reader. It needs no GitHub account and no token, it
is ordered newest first, and it is cheap to poll: the response carries an `ETag`
and `Cache-Control: max-age=0, private, must-revalidate`, so a reader revalidates
instead of downloading the feed again.

## What an entry means

- **Title** — `Release 2.5.0`, one entry per release tag.
- **Body** — the commits folded into that release, newest first.
- **Order** — the newest entry is the current release.

Because the feed is generated from tags, it reports a release as soon as the tag
exists. Draft or unpublished GitHub Release objects make no difference.

## Only semver tags are releases

Treat a tag as a repository release only when it matches:

```text
^[0-9]+\.[0-9]+\.[0-9]+$
```

Rule updates run on their own version line. `bin/release.sh <ver>` snapshots the
beta profile into `profiles/mwp-rules-v<ver>.*`, and when it is run with `--tag`
it also creates a `v<ver>` tag (for example `v208`), which shows up in the same
feed. That is a rules release, not a repository release — skip anything that does
not look like `X.Y.Z`. The old `push` tag left over from the 1.3.1 release is not
a release either.

## What is not a release

- **Beta rule changes** — commits to `profiles/mwp-rules-beta.json`. They appear on
  the [Beta rules page](../reference/beta-rules.md) and in the feed only after they
  are promoted to a numbered release.
- **Documentation and generator updates** — the docs site republishes on every push
  to `main`, so a page can be newer than the newest release tag.

## Why not the version file or "latest release"

- **`VERSION` on `main`** agrees with the current tag right after a release, but
  `bin/release.sh` also rewrites it as `X.Y+1.0` for a rules release with no tag.
  A poller on that file can therefore announce a release that never happened, and
  it tracks the tip of `main` rather than a tagged commit.
- **GitHub's "Latest release" and "Watch → Custom → Releases"** only see Release
  objects. On 2026-10-29 `/releases/latest` still returned `2.3.1` while the tags
  had moved to `2.5.0`, and older versions sit as drafts, so that path is not used.

## Fallback: ask git directly

With git installed there is no need for the feed or the API:

```bash
git ls-remote --tags --refs https://github.com/managingwp/cloudflare-wordpress-rules.git \
  | awk '{sub("refs/tags/","",$2); print $2}' \
  | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' \
  | sort -V | tail -1
```

That prints the newest release tag. Compare it with the tag in your checkout
(`git describe --tags --abbrev=0`) to see whether you are behind; the project does
not self-update.
