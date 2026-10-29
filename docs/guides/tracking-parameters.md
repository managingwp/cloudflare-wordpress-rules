---
title: Tracking parameters
description: Why blocking on trk, fbclid, gclid, msclkid or utm_* blocks real visitors, and what to match instead.
---

# Tracking parameters

Never block on a tracking parameter alone. Parameters like `trk`, `fbclid`,
`gclid`, `msclkid` and `utm_*` are appended to links that real people click, and
a rule that matches one of them blocks the visitors you want.

## Why they appear on real traffic

| Parameter | Added by | Why a visitor arrives with it |
| --- | --- | --- |
| `trk` | LinkedIn | Appended to every link shared in a public post or job listing, for example `trk=public_post-text`. Every reader who clicks through carries it. |
| `fbclid` | Meta / Facebook | Click identifier on links shared to Facebook, Instagram and Messenger. |
| `gclid` | Google Ads | Click identifier on paid search results. Blocking it blocks the campaign you paid for. |
| `msclkid` | Microsoft Advertising | The same click identifier for Bing and Microsoft Ads. |
| `utm_*` | Anything | Campaign tags (`utm_source`, `utm_medium`, `utm_campaign`, `utm_term`, `utm_content`) added by newsletters, CRM links, QR codes and social schedulers. |

These parameters identify the post, the advertisement or the campaign — not the
visitor. They are also not a sign of automation: a single human click carries
exactly one of them.

## Match the abnormal part instead

A tracking parameter tells you how a request arrived. What you actually want to
block is the thing that makes the request unusable — a malformed structure, an
impossible length, a repeated fragment. Match that:

```text
(lower(http.request.uri.query) contains "%2f%3fpage%3d")
```

That expression matches an encoded `/?page=` fragment anywhere in the query. It
does not care whether the request also carries `trk=public_post-text`, and a
normal arrival from a LinkedIn post does not match it.

## Case sensitivity

Cloudflare's `contains` is case-sensitive, and URL encodings are not normalised
between clients: the same fragment arrives as `%2f%3fpage%3d` from one client and
`%2F%3Fpage%3D` from another. Without `lower()` an uppercase variant walks
straight through the rule — which means the rule looks deployed and does
nothing.

Wrap the field, not the literal:

```text
(lower(http.request.uri.query) contains "%2f%3fpage%3d")
```

Worked examples against that expression:

| Query string | Matches | Why |
| --- | --- | --- |
| `trk=public_post-text%2F%3Fpage%3D3` | yes | encoded `/?page=` present, in mixed case |
| `trk=public_post-text` | no | a tracking parameter on its own |
| `page=2/` | no | a trailing slash, not an encoded fragment |
| `page=2%2F%2F%3Fpage%3D3` | yes | the chained `//?page=` form the attack produced |
| `page=3&fbclid=abc123` | no | a normal page with a click identifier |

## Strip, do not block, when a human is clicking

If the goal is a clean, cacheable URL rather than protection, remove the
parameter instead of rejecting the request:

- a **URL Rewrite Transform Rule** that removes the query component, so the
  request continues to the canonical page; or
- a **Redirect Rule** (301) that sends the visitor to the clean URL.

Either keeps the visitor, keeps the response cacheable, and stops tracking
parameters from fragmenting your cache into thousands of single-hit keys.

Blocking is still right when there is no human to serve. Tracking parameters are
what legitimate traffic looks like, so the decision is about the *rest* of the
request: if the signature is a structural anomaly that no browser produces,
block it and leave the parameter alone.

## Before you deploy

1. **Test against legitimate examples first.** At minimum: a bare
   `?trk=public_post-text`, `/jobs/?page=2`, `?page=2/`, `?page=2&fbclid=x` and a
   normal `?page=3`. All five must not match.
2. **Check the encoding, not just the words.** Confirm the expression matches
   the mixed-case variant, and confirm it does not match the plain parameter.
3. **After deploying, read Security → Events** filtered to the rule and look for
   matches whose query does not carry the attack signature. That set is your
   false-positive list; it should be empty.
4. **Watch the cache.** A drop in cache-hit ratio, or 502/504 responses at the
   origin while the rule shows matches, means the rule is either too broad or
   positioned behind something expensive.

## Related

- [Nested pagination cache-busting flood](../incidents/2026-10-pagination-cache-busting-flood.md)
  — the incident where a tracking parameter shared a request with a
  cache-busting payload, and the rule that separated them.
- [Block response](block-response.md) — customising what a blocked visitor sees.
- [Rate limiting](rate-limiting.md) — the alternative when the traffic is real
  but too fast.
