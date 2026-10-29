---
title: Docs site
description: Build, preview and publish the Docusaurus documentation site.
---

# Docs site

The documentation site is a [Docusaurus 3](https://docusaurus.io/) project in
`website/`. The content lives in `docs/` at the repository root; the site config
points at it with `path: '../docs'`.

## Layout

```text
docs/                  documentation content (Markdown)
  getting-started/
  guides/
  commands/
  incidents/           incident registry: one record per situation
  reference/
    cloudflare-rulesets/
    history/
  contributing/
website/               Docusaurus config, theme and build
  docusaurus.config.js
  sidebars.js
  src/css/custom.css
  static/
    generator/         client-side WAF rule generator (served at /generator/)
```

Anything in `website/static/` is copied verbatim into the build. The rule
generator lives there, so the site publishes it at `/generator/` with no extra
build step; see [the rule generator guide](../tools/rule-generator.md).

## Local development

```bash
cd website
npm install
npm start
```

The dev server serves the site at
`http://localhost:3000/cloudflare-wordpress-rules/`.

```bash
cd website
npm run build     # static build into website/build
npm run serve     # serve the built site locally
```

The build fails on broken internal links and broken Markdown links
(`onBrokenLinks: 'throw'` and `onBrokenMarkdownLinks: 'throw'`), so a green
build is the link check.

## Generated pages

These pages are written by the build scripts and must not be edited by hand:

| Page | Generator |
| --- | --- |
| `docs/reference/beta-rules.md` | `bin/build.sh generate-md` |
| `docs/reference/stable-rules.md` | `bin/build.sh generate-md` |
| `docs/changelog.md` | `bin/build.sh generate-readme` |

`profiles/<profile>.md` and the `CHANGELOG.md` at the repository root are
generated from the same sources and stay in sync.

## Publishing

Publishing runs in GitHub Actions (`.github/workflows/docs.yml`) on every push
to `main` that touches `docs/**`, `website/**` or the workflow itself, and can
be triggered manually with **Run workflow**.

Publish target: `https://managingwp.github.io/cloudflare-wordpress-rules/`.

One-time repository setting: **Settings → Pages → Build and deployment →
Source: GitHub Actions**. No `gh-pages` branch is used.

The site is configured with:

- `url: 'https://managingwp.github.io'`
- `baseUrl: '/cloudflare-wordpress-rules/'`
- `routeBasePath: '/'` — documentation is the whole site
- `trailingSlash: false`

If the repository is renamed or a custom domain is added, update `url` and
`baseUrl` in `website/docusaurus.config.js` in the same change.

## Adding a page

1. Create the Markdown file under `docs/` with front matter (`title`,
   `description`).
2. Add its doc ID to `website/sidebars.js`.
3. Link it from a related page using a relative `.md` link.
4. Run `npm run build` in `website/` before committing.

## Incident records

Pages under `docs/incidents/` are **content, not code**: adding or editing one
does not bump `VERSION`, does not renumber rules, and does not imply a rules
release. They are published by the docs workflow on the next push to `main`.

Two checks cover them:

```bash
bash tests/test-incidents.sh    # schema, placeholders, section order, domains
bash tests/test-docs-site.sh    # front matter, sidebar membership, links
```

The record format and the anonymisation rule are in
[the incident schema](../reference/incident-schema.md); the client-domain rule
is in `AGENTS.md` under **Client Confidentiality in Documentation**.
