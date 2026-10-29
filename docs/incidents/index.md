---
title: Incidents
slug: /incidents
description: One record per situation observed on a real site — signature, evidence, mitigation and the false positives to test before deploying a rule.
---

# Incidents

A registry of situations observed on real managed WordPress sites that are
likely to recur elsewhere: what the traffic looked like, why it worked, the rule
that stopped it, and the legitimate requests that must not be blocked.

Every record follows [the incident schema](../reference/incident-schema.md) and
identifies the affected deployment by placeholder (`site-a`, `site-b`), never by
domain.

| ID | Situation | Class | Status | First seen | Instances | Rule |
| --- | --- | --- | --- | --- | --- | --- |
| [INC-2026-10-28-01](2026-10-pagination-cache-busting-flood.md) | Nested pagination cache-busting flood | `cache-busting-flood` | contained | 2026-10-28 | site-a | incident-only |

## Adding a record

1. Copy [the incident template](../contributing/incident-template.md) to
   `docs/incidents/<YYYY>-<MM>-<slug>.md`.
2. Fill the front matter and the eight sections — especially **Do not block**.
3. Add a row to the table above.
4. Run `bash tests/test-incidents.sh` and `npm --prefix website run build`.

The test enforces the schema, the `site-a` placeholders and the section order,
and it sweeps the records for hostnames. It cannot detect a bare site title, so
read the record before committing it.
