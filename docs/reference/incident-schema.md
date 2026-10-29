---
title: Incident schema
description: The record format for the incident registry — required fields, allowed values, body sections and redaction rules.
---

# Incident schema

The incident registry records situations that were observed on a real site and
are likely to recur elsewhere: a flood that exhausted PHP-FPM, a scrape that
looked like a DDoS, a signup wave from a proxy range. Each record is one
Markdown page under `docs/incidents/`, and this page is its contract.

The registry exists so a rule found under pressure on one site can be applied
to the next site in minutes — with the false positives already documented, not
rediscovered in production.

## When to write a record

Write one when either is true:

- the situation can recur on another site you manage, and the response was
  worth keeping; or
- the response produced a rule, a challenge, or an origin change that someone
  will need to understand later.

Do not write one for a single-site incident with no reusable lesson. Those
belong in the private tracker.

## File naming

```text
docs/incidents/<YYYY>-<MM>-<slug>.md
docs/incidents/2026-10-pagination-cache-busting-flood.md
```

The year and month of the filename must match the `incident_id` seen date. The
slug names the mechanism, not the site — `pagination-cache-busting-flood`,
never a domain.

## Front matter

```yaml
---
title: Nested pagination cache-busting flood
description: Unique encoded page URLs exhausted PHP-FPM on one managed WordPress site.
incident_id: INC-2026-10-28-01
status: contained
attack_class: cache-busting-flood
first_seen: 2026-10-28
last_seen: 2026-10-29
recurrences: []
severity: high
instances:
  - { date: 2026-10-28, site_ref: site-a }
rules: []
confidence: observed
tags: [cache-busting, php-fpm, ipv6, pagination, free-plan]
---
```

| Field | Required | Value |
| --- | --- | --- |
| `title` | yes | Page title. Names the mechanism, never a client. |
| `description` | yes | One line for the docs index and search results. |
| `incident_id` | yes | `INC-YYYY-MM-DD-NN`, where the date is the first sighting and `NN` orders records from the same day. |
| `status` | yes | `active` (still being mitigated), `contained` (response deployed), `historical` (no longer expected to recur). |
| `attack_class` | yes | One of the closed list below. |
| `first_seen` | yes | `YYYY-MM-DD`. |
| `last_seen` | yes | `YYYY-MM-DD`. |
| `recurrences` | no | Dates the same signature returned after the first response. Omit when empty. |
| `severity` | yes | `low`, `medium`, `high` or `critical`, by the anchors below. |
| `instances` | yes | One entry per affected deployment: `{ date, site_ref }`. |
| `rules` | no | Rule ids that now ship in a profile. Empty when the expression is incident-only. |
| `confidence` | yes | `observed` (seen in this deployment), `provider-reported` (from an upstream or hosting provider), `inferred` (deduced from partial evidence). |
| `tags` | yes | Free-form tags; Docusaurus publishes `/tags/<slug>` index pages for them. |

### `attack_class`

`cache-busting-flood`, `credential-stuffing`, `scraper-flood`,
`referral-flood`, `xmlrpc-abuse`, `upload-probe`, `comment-spam`,
`crawler-misbehaviour`, `other`.

Add a class only when a record cannot be described by one of these; the list is
closed so the index stays filterable.

### `severity`

| Value | Anchor |
| --- | --- |
| `low` | Noise. No measurable impact on visitors or the origin. |
| `medium` | Degraded performance or a broken feature for some visitors, no outage. |
| `high` | Partial outage, or sustained failure for a share of visitors. |
| `critical` | Site-wide outage, data exposure, or an origin compromise. |

### `site_ref` placeholders

Every deployment is identified as `site-a`, `site-b`, and so on — the closed
set `site-a` … `site-z`, allocated in the private tracker. The mapping never
enters the repository; see **Client Confidentiality in Documentation** in
`AGENTS.md`.

`tests/test-incidents.sh` enforces this: a `sites:` key is an error, and every
`site_ref` must match `^site-[a-z]$`.

## Body sections

Use these `##` headings, in this order. The test checks that none is missing and
that the order holds.

| Section | What goes in it |
| --- | --- |
| **Summary** | Two sentences in plain language: what happened and what fixed it. Written for someone who has not seen the site. |
| **Signature** | The abnormal part of the request, normalised, plus one redacted example. State what varies between requests and what does not. |
| **Evidence** | Volume and shape: request count, distinct IPs, ASNs, requests per IP, peak rate, response-code mix, failure timing. Link to the private tracker for the site mapping. |
| **Why it worked** | The mechanism that turned traffic into damage — a cache that never hits, a query per request, an unbounded worker pool. |
| **Mitigation** | What was deployed, in evaluation order: rule expression, position, plan tier, then any stopgap and its step-down condition. |
| **Do not block** | At least four legitimate look-alikes, each with its expected non-match, and the reason they look similar. This section is why the record is safe to copy. |
| **Origin fix** | What Cloudflare cannot do for you: the application, web-server or origin-network change that removes the root cause. |
| **Detection** | The query that proves the rule fires only on attacks, and what a false positive looks like in it. |

## Rules are referenced, not copied

An incident expression is documentation until it is promoted. Two cases:

- **Shipped rule.** The rule exists in `profiles/default.json` or
  `profiles/mwp-rules-beta.json`. List its id in `rules:` and show the
  expression, so a reader can find its position and companions on the stable or
  beta rules page. The profile stays the single source of the expression.
- **Incident-only expression.** The rule is too specific, or too costly in
  Free-plan rule slots, to ship to every site. Leave `rules:` empty, show the
  expression in a fenced block, and say plainly that it is not in a profile.

Never let a record's copy of a shipped expression drift from the profile. If
the profile changes, update the record in the same commit.

## Redaction

- No raw request lines. Quote the abnormal field, not the whole line.
- Replace query values with `<redacted>`; keep the parameter names, which are
  the signature.
- Omit client IPs, or shorten them to a network. Keep ASNs, provider ranges and
  user-agent strings — they identify the attacker, not the visitor.
- Never a credential, session id, email address, order number or full URL that
  contains one.
- No screenshots of a dashboard that shows the site name, and no exported
  console link that embeds it.

## Authoring flow

1. Copy `docs/contributing/incident-template.md` to
   `docs/incidents/<YYYY>-<MM>-<slug>.md`.
2. Fill the front matter and the eight sections. For a new class, reuse the
   closest existing record's wording rather than inventing structure.
3. Add a row to `docs/incidents/index.md`.
4. Run `bash tests/test-incidents.sh`, then `bash tests/test-docs-site.sh`.
5. Read the record once for brand names and site titles — the sweep catches
   hostnames only.

## Related pages

- [Profile format](profile-format.md) — the profile a shipped rule belongs to.
