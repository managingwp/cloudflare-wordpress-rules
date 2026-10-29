---
title: Incident template
description: Copy-paste skeleton for a new incident record, with every required field and section.
---

# Incident template

Copy this page to `docs/incidents/<YYYY>-<MM>-<slug>.md` and replace every
`TODO`. The contract — allowed values, severity anchors and redaction rules —
lives in `docs/reference/incident-schema.md`.

Keep the eight sections in the order below and delete none of them: a section
with nothing to say gets one sentence explaining why, not a deletion.

````markdown
---
title: TODO - name the mechanism, never a client
description: TODO - one line for the docs index.
incident_id: INC-YYYY-MM-DD-NN
status: TODO        # active | contained | historical
attack_class: TODO  # cache-busting-flood | credential-stuffing | scraper-flood | referral-flood
                    # | xmlrpc-abuse | upload-probe | comment-spam | crawler-misbehaviour | other
first_seen: YYYY-MM-DD
last_seen: YYYY-MM-DD
recurrences: []     # dates the same signature returned; omit when empty
severity: TODO      # low | medium | high | critical
instances:
  - { date: YYYY-MM-DD, site_ref: site-a }   # site-a ... site-z only
rules: []           # profile rule ids, or empty for an incident-only expression
confidence: TODO    # observed | provider-reported | inferred
tags: [TODO]
---

# TODO - incident title

## Summary

<!-- Two sentences: what happened, and what fixed it. No client names. -->

## Signature

<!-- The abnormal part of the request, normalised, plus one redacted example.
     Say what varies between requests and what does not. -->

```text
TODO - redacted example
```

## Evidence

<!-- Volume and shape: requests, distinct IPs, ASNs, requests per IP, peak rate,
     response-code mix, failure timing. Link the private tracker for the site. -->

## Why it worked

<!-- The mechanism that turned traffic into damage: cache that never hits,
     query per request, unbounded worker pool. -->

## Mitigation

<!-- In evaluation order: expression, rule position, plan tier. Then any
     stopgap and the condition that steps it down. Say whether the expression
     ships in a profile. -->

```text
TODO - expression
```

## Do not block

<!-- At least four legitimate look-alikes with their expected non-match, and
     why each looks similar. This is the section that makes the record safe to
     copy. Link the tracking-parameters guide when the trap is a parameter. -->

| Legitimate request | Expected | Why it looks similar |
| --- | --- | --- |
| TODO | no match | TODO |

## Origin fix

<!-- What Cloudflare cannot do: application, web-server or origin-network
     change that removes the root cause. -->

## Detection

<!-- The query that proves the rule fires only on attacks, and what a false
     positive looks like in it. -->
````

After filling it in, add a row to `docs/incidents/index.md` and run
`bash tests/test-incidents.sh` and `bash tests/test-docs-site.sh`.
