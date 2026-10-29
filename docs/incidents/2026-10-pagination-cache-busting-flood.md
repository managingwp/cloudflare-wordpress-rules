---
title: Nested pagination cache-busting flood
description: Unique encoded page URLs exhausted PHP-FPM on one managed WordPress site, with normal user agents and roughly one request per IP.
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

# Nested pagination cache-busting flood

## Summary

On 28–29 October 2026 one managed WordPress site absorbed roughly 453,000
requests in about four hours, every one of them a cache miss. Each request
carried a unique, ever-growing pagination URL, so page caching did nothing and
PHP-FPM was exhausted inside a minute; a single block rule on the encoded
pagination fragment stopped it, and a pagination fix at the origin removed the
way the URLs grew.

## Signature

A query string containing repeated encoded `/?page=N` fragments, six to fifty
or more levels deep, with `N` between 1 and 15:

```text
/jobs/?trk=public_post-text%2F%3Fpage%3D3%2F%2F%3Fpage%3D10%2F%2F%3Fpage%3D4<redacted>
```

- **Stable:** the encoded sequence `%2f%3fpage%3d` — URL-encoded `/?page=` — and,
  at deeper levels, `%2f%2f%3fpage%3d` for `//?page=`.
- **Varies:** the depth (6 to 50+), the page number at each level (1 to 15), and
  whatever parameter the chain started from — in the observed traffic a
  LinkedIn click-tracking parameter shared in a public post.

The first request in a chain is an ordinary page with a normal page value. Every
subsequent link appends the next fragment instead of replacing the page number,
so each visitor mints a new, longer URL — and each unique URL is a new cache
key.

## Evidence

| Measure | Value |
| --- | --- |
| Duration | about four hours across 28–29 October 2026 |
| Requests | about 453,000 |
| Distinct client IPs | about 337,000 |
| ASNs | 927 |
| Requests per IP | about 1.35 |
| Peak rate | about 5,000 requests per minute |
| Origin failure | PHP-FPM pool exhausted inside one minute |
| Response mix | 502 at 0.000 s, 504 at exactly 60 s, mass 499s from clients giving up |

The three failure modes together are the fingerprint of worker exhaustion, not
of a network flood: 502 responses returned instantly because no worker was free
to accept the connection, 504 responses landed at exactly the 60-second gateway
timeout, and 499s recorded the visitors and crawlers who left first.

Two common defences did not apply:

- **User agents were useless.** They were ordinary rotating Chrome strings,
  changing between waves, with no shared token to match.
- **Per-IP rate limiting and geo blocks were useless.** At 1.35 requests per IP
  and 927 ASNs, the traffic looked like a large audience rather than a flood.

Later waves came mostly from IPv6 proxy ranges at FiberPower LLC (AS214483) and
Zenlayer (AS62610), with the same URL requested by three to five IPs inside the
same second. That is consistent with a pool of proxies walking a shared queue of
URLs, not with a browser population.

The site this happened to is recorded in the private tracker as `site-a`.

## Why it worked

The page cache keys on the full URL including the query string. Because every
request had a unique URL, no request could ever hit an existing cache entry, so
each one reached PHP and rendered a full page — search, pagination, templates
and all. A pool of PHP-FPM workers is small by design; once every worker is
inside a full render, new connections queue, the queue outgrows the gateway
timeout, and the site fails at the edge while the origin stays busy.

The amplification that kept it going was at the origin, not in the attack: the
site's pagination appended `/?page=N` to the current URL instead of replacing
the page value, so a normal visitor or crawler produced `?page=2/`, then
`?page=2//?page=3`, then `?page=2//?page=3//?page=4`, and so on. Translation
proxies that follow links then crawled those growing URLs on their own.

## Mitigation

One custom rule, first position, `Block`:

```text
(lower(http.request.uri.query) contains "%2f%3fpage%3d")
```

- **Plan tier:** fits the Free plan; it used the site's single available custom
  rule slot.
- **Position:** first. Every later rule — including the login challenge — is
  skipped for a request this rule blocks, which is the point: these requests are
  never legitimate.
- **`lower()`:** Cloudflare's `contains` is case-sensitive, and the encoding
  case is not stable across clients. Without `lower()` an uppercase `%2F%3F`
  variant walks straight through.

An optional second rule, if the ranges stay busy after the first is live:

```text
(ip.src.asnum in {214483 62610})
```

with the `Managed Challenge` action — not `Block`, because those providers also
carry ordinary traffic.

**Under Attack Mode is a stopgap, not a fix.** It stops the bleeding but
challenges every visitor and buries the signature in Security Events, which
makes the false-positive check impossible while it is on. Step down to Security
Level `High` once the targeted rule has been live and traffic has been clean for
30 minutes.

**This expression is not shipped in a profile.** It stays an incident-only
expression: the signature is specific enough that it does not belong in
`default`, where it would spend a custom-rule slot on every site, and the same
protection is available by pasting the expression above.

## Do not block

The rule matches the *encoded* fragment `%2f%3fpage%3d`, never `page=` on its
own. These requests are legitimate and must not match:

| Request | Expected | Why it looks similar |
| --- | --- | --- |
| `/?trk=public_post-text` | no match | LinkedIn click tracking appended to every link shared in a public post — the query has a tracking parameter and no encoded pagination |
| `/jobs/?page=2` | no match | ordinary pagination: a single, plain page value |
| `/jobs/?page=2/` | no match | a trailing slash after the page value, which early builds of the broken pagination produced |
| `/jobs/?page=2&fbclid=<redacted>` | no match | a click id appended to a normal page |
| `/jobs/?page=3` | no match | a deeper page still carrying one plain value |

Test the expression against all five before deploying. A block rule on the
tracking parameter alone would have blocked every visitor arriving from the
LinkedIn post that started the chain.

## Origin fix

Cloudflare shortened the outage; it did not remove the cause. The origin needs
four changes:

1. **Build pagination by replacing the page value**, so `?page=2` links to
   `?page=3` rather than `?page=2//?page=3`. This is the actual defect.
2. **301 any URL carrying more than one page value** to the canonical
   single-value URL, so existing links and crawler backlogs collapse instead of
   multiplying.
3. **Lock the origin to Cloudflare.** Firewall the origin to Cloudflare's
   address ranges and enable Authenticated Origin Pulls. On GridPane this is
   server-wide, so check the other sites on the server before enabling it.
4. **Lower `fastcgi_read_timeout` to around 20 seconds** so a stuck worker frees
   itself three times faster than the 60-second default, and a repeat event
   degrades instead of collapsing.

Translation proxies amplify this class of bug on their own — GTranslate
(AS402674, 64.7.195.0/22) and OVH (54.38.227.216–223) crawled the growing URLs
without any attacker involvement. Fixing pagination is what stops them.

## Detection

After deploying, filter Security → Events by the rule and then look for matches
whose query string does **not** contain `%2f%3fpage%3d`. That set is the
false-positive list, and it should be empty.

Two checks are worth watching for the first day:

- A match on `/jobs/?page=2/` means the expression is broader than intended —
  it should only fire on the encoded fragment, never on a plain trailing slash.
- A rising 502/504 share at the origin while the rule shows matches means the
  rule is positioned after something more expensive, or the origin is still
  being reached directly.

The clean signal is the shape of the traffic, not the request count: unique
pagination URLs per second returning to normal, and 499s disappearing.
