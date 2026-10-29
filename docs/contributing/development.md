---
title: Development
description: Build, test and release the repository.
---

# Development

## Repository conventions

Contributor and agent conventions live in
[`AGENTS.md`](https://github.com/managingwp/cloudflare-wordpress-rules/blob/main/AGENTS.md).
It covers commit style, the beta-channel workflow, the release-notes contract
and the documentation layout.

## Build

```bash
# Regenerate profile markdown, generated docs pages and the README beta pointer
bin/build.sh generate-md

# Regenerate CHANGELOG.md and the docs changelog page
bin/build.sh generate-readme

# Everything
bin/build.sh
```

`bin/build.sh` requires `jq`. The docs build additionally requires Node 18+ and
is documented in [the docs site guide](docs-site.md).

## Tests

The offline suite needs no Cloudflare credentials and never modifies tracked
files:

```bash
bash tests/test-docs-site.sh
bash tests/test-beta-readme.sh
bash tests/test-beta-perplexity.sh
bash tests/test-profile-resolution.sh
bash tests/test-print-profile.sh
bash tests/test-generator.sh
```

`tests/test-generator.sh` runs the rule builder under Node, so the generator and
`profiles/*.json` cannot drift. It also builds the docs site, to prove
`/generator/` survives the Docusaurus build.

## Releasing

Rules releases and repository releases are separate:

- **Rules release** — `bin/release.sh <version>` snapshots the beta profile,
  repoints `default.*`, regenerates documentation and bumps `VERSION`. It does
  not create a git tag.
- **Repository release** — a semver tag cut from a clean tree after the offline
  tests pass; `VERSION` and the tag move together.

See [profile management](../guides/profile-management.md) for the beta →
release flow.

## Plans

Work is planned in `plans/` (the `plans/` directory is a symlink to the plans
hub). Use `pgf list` / `pgf next` to see open plans and the next task.

## Documentation

New documentation goes into `docs/` — never at the repository root. See
[the docs site guide](docs-site.md).
