---
title: Profile management
description: The beta → release workflow for rule changes.
---

# Profile management

The repository uses a **beta → release** workflow.

- **`profiles/mwp-rules-beta.json`** — staging profile for rule changes (IPs,
  user agents, expressions).
- **`profiles/default.json`** — symlink to the latest numbered release; use it
  as the `default` selector.
- **`profiles/mwp-rules-v<NNN>.json`** — versioned release snapshots.

Beta rules are always published at the top of the
[Beta rules page](../reference/beta-rules.md), which
[`bin/build.sh generate-md`](https://github.com/managingwp/cloudflare-wordpress-rules/blob/main/bin/build.sh)
regenerates from the beta profile. Editing beta rules needs no version bump, no
tag and no release.

Profile selectors resolve by **filename first** (`<name>.json`), then by the
profile's internal `name` field. So `default` always targets the latest release,
and any `Name` shown by `list-profiles` (for example `default-calendar`) is also
a valid selector.

## Daily workflow (editing rules)

```bash
# 1. Edit profiles/mwp-rules-beta.json
# 2. Regenerate the profile markdown and the docs beta page
bin/build.sh generate-md

# 3. Commit
git add profiles/mwp-rules-beta.* docs/reference/beta-rules.md README.md
git commit -m "feat: update beta rules"
```

## Deploying beta rules to test

```bash
./cloudflare-wordpress-rules -d staging.example.com -c create-rules mwp-rules-beta
```

## Promoting beta to a numbered release

Rules versions are independent of the repository version. `bin/release.sh`
snapshots the beta profile, repoints the `default` symlinks and bumps
`VERSION`; it does not create a repository tag.

```bash
# Create rules release 208 from beta
bin/release.sh 208

# Commit the release files
git add profiles/mwp-rules-v208.* profiles/default.* VERSION
git commit -m "feat: release mwp-rules-v208"

# Refresh the generated documentation
bin/build.sh generate-md
bin/build.sh generate-readme
```

Do **not** create a `v208` git tag: repository tags track the semver repository
release, not the numeric rules version.

## Deploying the stable release

```bash
# default always points to the latest release
./cloudflare-wordpress-rules -d domain.com -c create-rules default

# Or upgrade an existing deployment in place
./cloudflare-wordpress-rules -d domain.com -c upgrade-default-rules
```

## Related

- [Beta rules](../reference/beta-rules.md)
- [Stable rules](../reference/stable-rules.md)
- [Profile format](../reference/profile-format.md)
