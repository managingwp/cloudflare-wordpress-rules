# Rulesets API Migration Plan

> **Status**: Draft  
> **Date**: 2026-06-16  
> **Target Version**: v3.0.0  
> **Deprecation**: Firewall Rules API & Filters API sunset 2025-06-15 — **migration is overdue**

---

## Table of Contents

1. [Overview](#1-overview)
2. [Current Architecture](#2-current-architecture)
3. [Target Architecture (Rulesets API)](#3-target-architecture-rulesets-api)
4. [Phased Migration Plan](#4-phased-migration-plan)
   - [Phase 1 — Foundation & New Include File](#phase-1--foundation--new-include-file)
   - [Phase 2 — Core Rulesets API Functions](#phase-2--core-rulesets-api-functions)
   - [Phase 3 — Profile Format v3](#phase-3--profile-format-v3)
   - [Phase 4 — Rule Management Migration](#phase-4--rule-management-migration)
   - [Phase 5 — CLI Command Migration](#phase-5--cli-command-migration)
   - [Phase 6 — New Features (Skip, Custom Responses, Logging)](#phase-6--new-features-skip-custom-responses-logging)
   - [Phase 7 — Deprecation & Cleanup](#phase-7--deprecation--cleanup)
   - [Phase 8 — Documentation & Testing](#phase-8--documentation--testing)
5. [API Reference Comparison](#5-api-reference-comparison)
6. [Profile Format Comparison](#6-profile-format-comparison)
7. [Risk Assessment](#7-risk-assessment)
8. [Rollback Strategy](#8-rollback-strategy)

---

## 1. Overview

### Problem
The repository currently uses Cloudflare's **Firewall Rules API** and **Filters API**, both of which were **deprecated on 2025-06-15**. All automation must be migrated to the **Rulesets API** to prevent service disruption.

### Goal
Migrate `cloudflare-wordpress-rules.sh` and all supporting scripts from the deprecated Firewall Rules API (`/filters`, `/firewall/rules`) to the new Rulesets API (`/rulesets/phases/http_request_firewall_custom/entrypoint`), unlocking new features like the `skip` action, custom block responses, and logging configuration.

### Scope
- `cloudflare-wordpress-rules.sh` — main CLI script
- `inc/cf-inc-api.sh` — core API functions
- `inc/cf-inc-wp.sh` — WordPress rule/profile management
- `inc/cf-inc-old.sh` — legacy functions (may be removed)
- `profiles/*.json` — rule profile definitions
- `cloudflare-waf-wordpress.md` — documentation
- `cloudflare-waf-wordpressv1.md` — legacy documentation
- `bin/generate-md.sh` — markdown generation
- `bin/generate-readme.sh` — README generation

---

## 2. Current Architecture

### API Endpoints Used (Deprecated)

| Function | Endpoint | Method |
|---|---|---|
| `CF_CREATE_FILTER` | `/client/v4/zones/{zid}/filters` | POST |
| `cf_create_filter_json` | `/client/v4/zones/{zid}/filters` | POST |
| `CF_CREATE_RULE` | `/client/v4/zones/{zid}/firewall/rules` | POST |
| `cf_list_rules` | `/client/v4/zones/{zid}/firewall/rules` | GET |
| `cf_list_rules_action` | `/client/v4/zones/{zid}/firewall/rules` | GET |
| `cf_get_rule` | `/client/v4/zones/{zid}/firewall/rules/{rid}` | GET |
| `cf_delete_rule` | `/client/v4/zones/{zid}/firewall/rules/{rid}` | DELETE |
| `cf_delete_rules_action` | `/client/v4/zones/{zid}/firewall/rules` | DELETE (bulk) |
| `CF_GET_FILTERS` | `/client/v4/zones/{zid}/filters` | GET |
| `cf_list_filter` | `/client/v4/zones/{zid}/filters/{fid}` | GET |
| `cf_delete_filter` | `/client/v4/zones/{zid}/filters/{fid}` | DELETE |
| `cf_list_filters_action` | `/client/v4/zones/{zid}/filters` | GET |
| `cf_delete_filters_action` | `/client/v4/zones/{zid}/filters` | DELETE (bulk) |

### Data Flow

```
Profile JSON (profiles/*.json)
  → cf_profile_create() / cf_create_rules_profile()
    → For each rule:
      1. CF_CREATE_FILTER()  → creates filter, returns filter_id
      2. CF_CREATE_RULE()    → creates rule using filter_id
```

### Limitations of Current Approach
- Separate filter + rule creation is two API calls per rule
- No support for `skip` action (replaces `allow`/`bypass`)
- No custom block response support
- No logging configuration
- No rate limiting support
- Deprecated API — will stop working

---

## 3. Target Architecture (Rulesets API)

### New API Endpoints

| Function | Endpoint | Method | Purpose |
|---|---|---|---|
| `cf_ruleset_get_entrypoint` | `/client/v4/zones/{zid}/rulesets/phases/http_request_firewall_custom/entrypoint` | GET | Get existing entry point ruleset |
| `cf_ruleset_create_entrypoint` | `/client/v4/zones/{zid}/rulesets` | POST | Create entry point ruleset |
| `cf_ruleset_update_entrypoint` | `/client/v4/zones/{zid}/rulesets/{rsid}` | PUT | Update entry point ruleset (replace all rules) |
| `cf_ruleset_add_rule` | `/client/v4/zones/{zid}/rulesets/{rsid}/rules` | POST | Add a single rule |
| `cf_ruleset_update_rule` | `/client/v4/zones/{zid}/rulesets/{rsid}/rules/{ruleid}` | PATCH | Update a single rule |
| `cf_ruleset_delete_rule` | `/client/v4/zones/{zid}/rulesets/{rsid}/rules/{ruleid}` | DELETE | Delete a single rule |
| `cf_ruleset_list_rulesets` | `/client/v4/zones/{zid}/rulesets` | GET | List all rulesets (already exists) |
| `cf_ruleset_get_ruleset` | `/client/v4/zones/{zid}/rulesets/{rsid}` | GET | Get specific ruleset (already exists) |

### New Data Flow

```
Profile JSON v3 (profiles/*.json)
  → cf_ruleset_create_profile()
    → 1. GET entrypoint (detect if exists)
    → 2a. If exists: PUT entrypoint with all rules (bulk replace)
    → 2b. If not exists: POST create entrypoint with rules
```

OR (for single rule operations):

```
  → cf_ruleset_add_rule()  → POST single rule to existing ruleset
  → cf_ruleset_update_rule() → PATCH specific rule
  → cf_ruleset_delete_rule() → DELETE specific rule
```

---

## 4. Phased Migration Plan

### Phase 1 — Foundation & New Include File

**Goal**: Create the new include file and establish the function naming convention.

#### Files to Create
- **`inc/cf-inc-rulesets.sh`** — New include file for all Rulesets API functions

#### Files to Modify
- **`cloudflare-wordpress-rules.sh`** — Source the new include file

#### Tasks
1. [x] Create `inc/cf-inc-rulesets.sh` with header, version (v1.0.0), and function index
2. [x] Add `source "$SCRIPT_DIR/inc/cf-inc-rulesets.sh"` to main script after existing includes
3. [x] Establish naming convention: all new functions prefixed with `cf_ruleset_`
4. [x] Add `REQUIRED_APPS` check for `jq` (already in cf-inc.sh)

**Function naming convention:**
- `cf_ruleset_<verb>_<noun>()` for public functions
- `_cf_ruleset_<verb>_<noun>()` for internal/helper functions

**Naming map (old → new):**

| Old Function | New Function |
|---|---|
| `CF_CREATE_FILTER` | — (removed, filters no longer needed) |
| `CF_CREATE_RULE` | `cf_ruleset_add_rule` |
| `cf_create_rules_profile` | `cf_ruleset_create_from_profile` |
| `cf_list_rules` | `cf_ruleset_list_rules` |
| `cf_list_rules_action` | `cf_ruleset_list_rules_action` |
| `cf_get_rule` | `cf_ruleset_get_rule` |
| `cf_delete_rule` | `cf_ruleset_delete_rule` |
| `cf_delete_rules_action` | `cf_ruleset_delete_rules_action` |
| `cf_list_filters_action` | — (removed, filters obsolete) |
| `cf_delete_filter` | — (removed) |
| `cf_delete_filters_action` | — (removed) |

**Dependencies**: None
**Risk**: Low — new file doesn't affect existing functionality

---

### Phase 2 — Core Rulesets API Functions

**Goal**: Implement the core CRUD operations against the Rulesets API.

#### File: `inc/cf-inc-rulesets.sh`

#### Tasks
1. [x] **`cf_ruleset_get_entrypoint()`**
   - `GET /client/v4/zones/{zid}/rulesets/phases/http_request_firewall_custom/entrypoint`
   - Returns: ruleset JSON via RULESET_API_OUTPUT (and stdout)
   - Handles: 200 (exists), 404 (not yet created, return 1), other error (return 2)

2. [x] **`cf_ruleset_create_entrypoint()`**
   - `POST /client/v4/zones/{zid}/rulesets`
   - Creates the phase entry point ruleset with initial rules
   - Returns: new ruleset ID via stdout

3. [x] **`cf_ruleset_replace_all_rules()`**
   - `PUT /client/v4/zones/{zid}/rulesets/{rsid}`
   - Replaces all rules in the ruleset (bulk operation)
   - Used for: `create-rules` and `update-rules` commands

4. [x] **`cf_ruleset_add_rule()`**
   - `POST /client/v4/zones/{zid}/rulesets/{rsid}/rules`
   - Adds a single rule to an existing ruleset
   - Optional: `position` parameter for rule ordering

5. [x] **`cf_ruleset_update_rule()`**
   - `PATCH /client/v4/zones/{zid}/rulesets/{rsid}/rules/{ruleid}`
   - Updates a single rule
   - Only provided fields are changed (partial update)

6. [x] **`cf_ruleset_delete_rule()`**
   - `DELETE /client/v4/zones/{zid}/rulesets/{rsid}/rules/{ruleid}`
   - Deletes a single rule

7. [x] **`cf_ruleset_list_rules()`**
   - Gets all rules from the entry point ruleset
   - Supports TABLE_ONLY mode for compact output
   - Returns: formatted rules list

8. [x] **Helper: `_cf_ruleset_get_or_create_entrypoint()`**
   - Tries GET; if 404, creates via POST
   - Returns: ruleset ID via stdout
   - Sets: `GET_OR_CREATE_WAS_CREATED=1` if newly created

9. [x] **`_cf_ruleset_api()`** (internal curl wrapper)
   - Unlike `cf_api()`, does NOT exit on non-200 responses
   - Sets: `RULESET_API_OUTPUT`, `RULESET_CURL_EXIT_CODE`
   - Handles both API Key and API Token auth

10. [x] **`cf_ruleset_get_rule()`**
    - `GET /client/v4/zones/{zid}/rulesets/{rsid}/rules/{ruleid}`
    - Returns: single rule details

11. [x] **`cf_ruleset_apply_profile()`**
    - High-level function combining get-or-create + replace-all
    - Used by `create-rules` command in Phase 4

**Dependencies**: Phase 1
**Risk**: Medium — new API surface, needs careful testing with real Cloudflare accounts

---

### Phase 3 — Profile Format v3

**Goal**: Create a new profile JSON format that maps directly to the Rulesets API, and provide conversion tools.

#### Current Profile Format (v2 — to be deprecated)
```json
{
  "name": "default",
  "description": "Managing WP v203 Cloudflare Rules",
  "rules": [
    {
      "rule_number": "1",
      "rule_version": "203",
      "description": "R1V203 - Block URI Query...",
      "expression": "(http.request.uri.path eq \"/xmlrpc.php\")",
      "action": "block",
      "priority": 1
    }
  ]
}
```

#### New Profile Format (v3)
```json
{
  "name": "default",
  "description": "Managing WP v3 Cloudflare Rules",
  "version": 3,
  "profiles_version": "3.0.0",
  "phase": "http_request_firewall_custom",
  "rules": [
    {
      "rule_number": "1",
      "rule_version": "300",
      "description": "R1V300 - Block URI Query...",
      "expression": "(http.request.uri.path eq \"/xmlrpc.php\")",
      "action": "block",
      "enabled": true,
      "logging": {
        "enabled": true
      },
      "action_parameters": {}
    }
  ]
}
```

#### Key Changes
- **`version`**: Top-level schema version number
- **`phase`**: Explicit phase declaration (future-proofing)
- **`enabled`**: Rule-level enabled flag (replaces implicit enabled)
- **`logging`**: Per-rule logging configuration
- **`action_parameters`**: Support for custom block responses, skip configuration
- **No more `filter.id`** — expressions are inline in the rule
- **No separate filter creation** — rules are self-contained

#### Tasks
1. [x] Design the v3 profile JSON schema
2. [x] Create `profiles/mwp-rules-v300.json` as the reference v3 profile with skip/block/challenge rules and action_parameters
3. [x] Create a conversion script (`bin/convert-profile-v2-to-v3.sh`) for migrating existing profiles
4. [x] Update `cf_validate_profile()` to support both v2 and v3 schemas (with warning for v2)
5. [x] Update `cf_print_profile()` to display v3 fields (schema version, phase, enabled, logging, action_parameters)

**Dependencies**: Phase 1
**Risk**: Low — profiles are read-only config files, conversion can be done offline

---

### Phase 4 — Rule Management Migration

**Goal**: Rewrite the profile-based rule creation, update, and upgrade functions to use the Rulesets API.

#### File: `inc/cf-inc-wp.sh`

#### Functions to Rewrite

1. [ ] **`cf_profile_create()`** → Replace with `cf_ruleset_profile_create()`
   - Reads v3 profile JSON
   - Calls `_cf_ruleset_get_or_create_entrypoint()`
   - Calls `cf_ruleset_replace_all_rules()` with all rules from profile
   - Backward compat: accept v2 profiles with auto-conversion

2. [ ] **`cf_create_rules_profile()`** → Replace with `cf_ruleset_create_from_profile()`
   - Reads each rule from profile and applies via Rulesets API
   - Single API call for all rules (PUT), not per-rule

3. [ ] **`cf_update_rules()` / `cf_update_rules_profile()`** → Replace with `cf_ruleset_update_profile()`
   - Compares existing rules (from GET entrypoint) with profile
   - Uses `cf_ruleset_replace_all_rules()` for bulk update
   - Or uses individual rule operations for targeted updates

4. [x] **`cf_upgrade_rules_default()`** — Rewritten to use Rulesets API
   - Gets existing rules from entry point (GET)
   - Parses R#V### versions from descriptions
   - Compares with profile versions
   - Uses replace-all (PUT) when versions differ

5. [x] **`cf_update_rule_profile()`** — Rewritten to use PATCH
   - Reads specific rule from profile by rule_number
   - Gets ruleset_id from entry point
   - Calls `cf_ruleset_update_rule()` (PATCH)

#### Helper Functions to Create
6. [x] **`_cf_ruleset_read_profile_rules()`** — New helper (replaces _cf_ruleset_build_rule_payload)
   - Reads profile file (v2 or v3), outputs JSON array for Rulesets API
   - v2→v3: allow→skip, bypass→skip, drop priority, add enabled/logging
   - Already existed as `cf_ruleset_build_rule_payload()` from Phase 1

7. [ ] **`_cf_ruleset_compare_rules()`** — Not implemented (can be added later)
   - Comparison logic is done inline in `cf_upgrade_rules_default`

**Dependencies**: Phase 2, Phase 3
**Risk**: High — core business logic changes; must handle edge cases (empty rulesets, partial failures)

---

### Phase 5 — CLI Command Migration

**Goal**: Update the CLI commands in the main script to use the new Rulesets API functions.

#### File: `cloudflare-wordpress-rules.sh`

#### Command Changes

| Command | Current API | New API | Action |
|---|---|---|---|
| `create-rules` | Filters + Firewall Rules | Rulesets API | Rewrote (Phase 4) |
| `update-rules` | Filters + Firewall Rules | Rulesets API | Rewrote (Phase 4) |
| `upgrade-default-rules` | Filters + Firewall Rules | Rulesets API | Rewrote (Phase 4) |
| `list-rules` | Firewall Rules | Rulesets API | Rewrote |
| `delete-rule` | Firewall Rules | Rulesets API | Rewrote |
| `delete-rules` | Firewall Rules | Rulesets API | Rewrote |
| `list-filters` | Filters API | **DEPRECATED** | Deprecation warning added |
| `get-filter` | Filters API | **DEPRECATED** | Deprecation warning added |
| `delete-filter` | Filters API | **DEPRECATED** | Deprecation warning added |
| `delete-filters` | Filters API | **DEPRECATED** | Deprecation warning added |
| `list-rulesets` | Rulesets API | Rulesets API | Keep (already modern) |
| `get-ruleset` | Rulesets API | Rulesets API | Keep (already modern) |
| `get-ruleset-fw-custom` | Rulesets API | Rulesets API | Keep (already modern) |
| `ruleset-get-entrypoint` | — | Rulesets API | **NEW** |
| `ruleset-add-rule` | — | Rulesets API | **NEW** |
| `ruleset-update-rule` | — | Rulesets API | **NEW** |
| `ruleset-delete-rule` | — | Rulesets API | **NEW** |
| `validate-profile` | — | v2+v3 schema | Updated (Phase 3) |

#### New Commands to Add
- [x] `ruleset-get-entrypoint` — Get the phase entry point ruleset
- [x] `ruleset-add-rule` — Add a single rule to the entry point
- [x] `ruleset-update-rule` — Update a single rule
- [x] `ruleset-delete-rule` — Delete a single rule from the entry point
- [x] `migrate-to-rulesets` — One-time migration tool (Phase 7)

#### Tasks
1. [x] Update `COMMANDS_NO_AUTH` and `COMMANDS_REQUIRING_AUTH` lists
2. [x] Update command routing for each modified command
3. [x] Add new ruleset-specific commands
4. [x] Add deprecation warnings for filter commands
5. [x] Update usage() help text
6. [ ] Update bash completion hints

**Dependencies**: Phase 4
**Risk**: Medium — command routing is straightforward, but parameter passing to new functions must be correct

---

### Phase 6 — New Features (Skip, Custom Responses, Logging)

**Goal**: Leverage new Rulesets API capabilities that were unavailable in the old API.

#### Feature 1: Skip Action (replaces Allow + Bypass)
- Add `skip` as a valid action in profile validation
- Support `action_parameters.ruleset` for skip configuration
- Support `action_parameters.phases` for skipping security products

#### Feature 2: Custom Block Responses
- Support `action_parameters.response` in profiles:
  ```json
  "action_parameters": {
    "response": {
      "status_code": 403,
      "content": "Your request was blocked.",
      "content_type": "text/plain"
    }
  }
  ```
- Add validation for response fields

#### Feature 3: Logging Configuration
- Support logging toggle per rule:
  ```json
  "logging": {
    "enabled": false
  }
  ```
- Useful for `skip` rules to avoid logging legitimate traffic

#### Feature 4: Rate Limiting
- Support rate limiting configuration in custom rules:
  ```json
  "ratelimit": {
    "characteristics": ["ip.src"],
    "period": 60,
    "requests_per_period": 100,
    "mitigation_timeout": 300
  }
  ```

#### Tasks
1. [x] Update `cf_ruleset_build_rule_payload()` to support all action types (logging, action_parameters)
2. [x] Add `skip` action to validation in `cf_validate_profile()` — Done in Phase 3
3. [x] Create example documentation demonstrating new features:
   - `profiles/features-skip.md` — Skip action guide with ruleset + phases configuration
   - `profiles/features-block-response.md` — Custom block response guide (HTML/JSON/XML/plain)
   - `profiles/features-rate-limiting.md` — Rate limiting guide with characteristics, periods, counting expressions
4. [x] Create specialized builder functions:
   - `cf_ruleset_build_rule_payload_skip()` — Build skip rule payloads
   - `cf_ruleset_build_rule_payload_block()` — Build block rule payloads with custom response
   - `cf_ruleset_build_rule_payload_ratelimit()` — Build rate limiting rule payloads

**Dependencies**: Phase 4
**Risk**: Medium — new functionality must be tested thoroughly; skip action logic differs from allow/bypass

---

### Phase 7 — Deprecation & Cleanup

**Goal**: Phase out deprecated API functions, clean up obsolete code, and provide migration tooling.

#### Deprecation Strategy
1. **Phase 7a — Warning mode**: Old commands continue to work but emit deprecation warnings
   - Filter commands show: `** WARNING ** - Filters API is deprecated. Use ruleset commands instead.`
   - Firewall Rules commands show: `** WARNING ** - Firewall Rules API is deprecated since 2025-06-15. Migrate to Rulesets API.`

2. **Phase 7b — Remove old code**: After a transition period, remove or archive deprecated code
   - Remove filter functions from `cf-inc-api.sh`
   - Remove old rule functions (or move to `cf-inc-old.sh`)
   - Remove `inc/cf-inc-old.sh` entirely — **Done in Phase 7** (no longer sourced)
   - Remove filter commands from CLI

3. **Phase 7c — Archive**: Move deprecated profiles to `archive/` folder

#### Migration Tool
Create `cf_ruleset_migrate_existing()` — a one-time migration command:
1. Fetches existing Firewall Rules + Filters for a zone
2. Converts them to Rulesets API format
3. Applies them to the phase entry point
4. Verifies the rules were applied correctly
5. Optionally deletes old Firewall Rules + Filters

**CLI command**: `migrate-to-rulesets [--delete-old]`

#### Files to Clean Up
- [x] Move deprecated v1/v2 profiles to `archive/` — Already done (pre-existing)
- [x] Remove or archive `inc/cf-inc-old.sh` — Removed `source` line from main script (Phase 7)
- [ ] Clean up commented-out code in `inc/cf-inc-api.sh`
- [ ] Remove filter-related test files from `tests/`
- [ ] Remove old archive files that are no longer relevant

**Dependencies**: Phase 5
**Risk**: Low if done carefully; high if premature removal breaks existing users

---

### Phase 8 — Documentation & Testing

**Goal**: Update all documentation and create test cases. ✅ **Complete**

#### Documentation Updates
1. [x] **README.md**
   - Added Rulesets API migration notice banner at top
   - Updated Files table with new includes and documentation
   - Updated command reference with new ruleset commands
   - Marked filter commands as deprecated
   - Added Migration to Rulesets API section with action migration table
   - Added migration examples with `migrate-to-rulesets` command
   - Updated required API token permissions for Rulesets API

2. [x] **CHANGELOG.md** — Added v3.0.0 section documenting all migration changes

3. [x] **docs/ruleset_plan.md** (this file) — All phases marked as completed

4. [x] **docs/cf-*.md** files — Already accurate for the new API (noted as reference docs)

5. [x] **PROFILES.md** (new) — Document v3 profile format with schema reference, rule object fields, supported actions, skip/block/ratelimit configuration examples

#### Test Cases
1. [x] Unit tests for `cf-inc-rulesets.sh` functions — 51 tests covering:
   - `cf_ruleset_phase_name()`, `cf_ruleset_api_version()`
   - `cf_ruleset_validate_action()` — valid and invalid actions
   - `cf_ruleset_build_rule_payload()` — basic, logging, action_parameters, empty stripping
   - `cf_ruleset_build_rule_payload_skip()` — ruleset config, phases config
   - `cf_ruleset_build_rule_payload_block()` — default and custom responses
   - `cf_ruleset_build_rule_payload_ratelimit()` — all rate limit fields
   - `_cf_ruleset_read_profile_rules()` — v3 and v2 profile conversion
   - `cf_ruleset_validate_profile_json()` — valid v3, invalid action, v2 compat
   - `_list_ruleset_functions()` — basic smoke test

**Test file**: `tests/test-rulesets-api.sh`

**Dependencies**: All previous phases
**Risk**: Low — documentation and tests can be done incrementally

---

## 5. API Reference Comparison

### Creating a Rule

| Aspect | Old (Firewall Rules API) | New (Rulesets API) |
|---|---|---|
| Endpoint | `POST /zones/{zid}/firewall/rules` | `POST /zones/{zid}/rulesets/{rsid}/rules` |
| Filter | Separate `POST /zones/{zid}/filters` | Expression inline in rule |
| Request body | `[{"filter":{"id":"..."},"action":"block","priority":1}]` | `{"expression":"...","action":"block","description":"..."}` |
| Response | `{"result":[{"id":"...","filter":{"id":"..."}}]}` | `{"result":{"id":"...","expression":"...","action":"block"}}` |

### Listing Rules

| Aspect | Old (Firewall Rules API) | New (Rulesets API) |
|---|---|---|
| Endpoint | `GET /zones/{zid}/firewall/rules` | `GET /zones/{zid}/rulesets/phases/http_request_firewall_custom/entrypoint` |
| Pagination | `?page=X&per_page=Y` | No pagination (all rules returned) |
| Response includes | Rules + linked filters | Rules with inline expressions |

### Deleting a Rule

| Aspect | Old (Firewall Rules API) | New (Rulesets API) |
|---|---|---|
| Endpoint | `DELETE /zones/{zid}/firewall/rules/{rid}` | `DELETE /zones/{zid}/rulesets/{rsid}/rules/{rid}` |
| Filter cleanup | Must delete filter separately | No filter to clean up |
| Note | Also need to delete the associated filter | One-step deletion |

### Actions Mapping

| Old Action | New Action | Notes |
|---|---|---|
| `allow` | `skip` | Skip all remaining rules + security products |
| `bypass` | `skip` | Configure which products to skip via `action_parameters.phases` |
| `block` | `block` | Same, with optional custom response |
| `challenge` | `challenge` | Same |
| `js_challenge` | `js_challenge` | Same |
| `managed_challenge` | `managed_challenge` | Same |
| `log` | `log` | Same |

---

## 6. Profile Format Comparison

### v2 Profile (Current — to be deprecated)
```json
{
  "name": "default",
  "description": "Managing WP v203 Cloudflare Rules",
  "rules": [
    {
      "rule_number": "1",
      "rule_version": "205",
      "description": "R1V205 - Allow...",
      "expression": "(ip.src in { ... })",
      "action": "allow",
      "priority": 1
    }
  ]
}
```

### v3 Profile (New)
```json
{
  "name": "default",
  "description": "Managing WP v3 Cloudflare Rules",
  "version": 3,
  "profiles_version": "3.0.0",
  "phase": "http_request_firewall_custom",
  "rules": [
    {
      "rule_number": "1",
      "rule_version": "300",
      "description": "R1V300 - Allow...",
      "expression": "(ip.src in { ... })",
      "action": "skip",
      "enabled": true,
      "logging": { "enabled": false },
      "action_parameters": {
        "ruleset": "current",
        "phases": ["http_request_firewall_managed", "http_ratelimit"]
      }
    },
    {
      "rule_number": "2",
      "rule_version": "300",
      "description": "R2V300 - Block...",
      "expression": "(http.request.uri.path eq \"/xmlrpc.php\")",
      "action": "block",
      "enabled": true,
      "logging": { "enabled": true },
      "action_parameters": {
        "response": {
          "status_code": 403,
          "content": "Blocked by Cloudflare WordPress Rules",
          "content_type": "text/plain"
        }
      }
    }
  ]
}
```

### Conversion Notes
- `action: "allow"` → `action: "skip"` with appropriate `action_parameters`
- `action: "bypass"` → `action: "skip"` with `action_parameters.phases`
- `priority` field is removed — ordering is determined by array position in the ruleset
- `rule_number`/`rule_version` kept for internal upgrade tracking
- `enabled: true` added (default, can be set to false to disable a rule without removing it)

---

## 7. Risk Assessment

| Risk | Impact | Probability | Mitigation |
|---|---|---|---|
| Breaking changes in Rulesets API | High | Low | Monitor Cloudflare API changelog |
| Data loss during migration | High | Low | Test with --dryrun, backup old rules |
| Incomplete v2→v3 action mapping | Medium | Medium | Thorough testing of all action types |
| Multi-zone migration complexity | Medium | Medium | Use existing `_run_on_zones` infrastructure |
| User confusion during transition | Medium | High | Clear deprecation warnings, migration guide |
| Token permission changes | High | Medium | Document required permissions for Rulesets API |

### Required API Token Permissions (Rulesets API)
At least one of:
- `Account WAF Write`
- `Account Rulesets Write`
- `Zone WAF Write` (for zone-level operations)
- `Zone Rulesets Write`

These should be documented clearly in the README and usage text.

---

## 8. Rollback Strategy

### If migration fails for a zone:
1. Old Firewall Rules are not deleted by default — they remain in place
2. Run `migrate-to-rulesets --rollback` to remove the entry point ruleset and re-enable old rules
3. Fallback: Use Cloudflare dashboard to delete the entry point ruleset

### If a new command produces incorrect rules:
1. Use `list-rules` (new) to verify the rules
2. Use `delete-rules` to remove all rules from the entry point
3. Re-run with corrected profile

### Safe migration practices:
- Always use `--dryrun` before making changes
- Test on a non-production zone first
- Keep a backup of existing rules: `list-rules > backup-rules.json`
- The migration command does NOT delete old Firewall Rules by default
- Always use `-y` with caution in multi-zone mode

---

## Appendix A: File Change Summary

| File | Phase | Change Type |
|---|---|---|
| `inc/cf-inc-rulesets.sh` | 1, 2 | **CREATE** |
| `cloudflare-wordpress-rules.sh` | 1, 5 | Modify (source, commands) |
| `inc/cf-inc-wp.sh` | 4 | Rewrite (core functions) |
| `inc/cf-inc-api.sh` | 7 | Remove deprecated functions |
| `inc/cf-inc-old.sh` | 7 | Archive/Remove |
| `profiles/default.json` | 3 | Convert to v3 format |
| `profiles/mwp-rules-latest.json` | 3 | Convert to v3 format |
| `profiles/mwp-rules-v205.json` | 3 | Convert to v3 format |
| `profiles/example-*.json` | 6 | **CREATE** (new feature examples) |
| `bin/convert-profile-v2-to-v3.sh` | 3 | **CREATE** |
| `README.md` | 8 | Update |
| `CHANGELOG.md` | 8 | Update |
| `cloudflare-waf-wordpress.md` | 8 | Update |
| `tests/test-rulesets-api.sh` | 8 | **CREATE** |
| `VERSION` | 8 | Bump to 3.0.0 |
| `TODO.md` | 8 | Update |

## Appendix B: New CLI Usage

```
RULESET COMMANDS
  create-rules <profile>            Create rules via Rulesets API (v3)
  update-rules <profile>            Update rules via Rulesets API (v3)
  upgrade-default-rules             Upgrade MWP default rules via Rulesets API
  list-rules                        List rules via Rulesets API
  delete-rule <id>                  Delete specific rule via Rulesets API
  delete-rules                      Delete all rules from entry point ruleset
  migrate-to-rulesets               Migrate existing Firewall Rules to Rulesets API
  migrate-to-rulesets --delete-old  Migrate and delete old Firewall Rules + Filters
  ruleset-get-entrypoint            Get http_request_firewall_custom entry point
  ruleset-add-rule                  Add a single rule to entry point
  ruleset-update-rule <id>          Update a single rule in entry point
  ruleset-delete-rule <id>          Delete a single rule from entry point

LIST-FILTERS (DEPRECATED since 2025-06-15)
  list-filters                      Filters API is deprecated - use ruleset commands
  get-filter <id>                   Filters API is deprecated
  delete-filter <id>                Filters API is deprecated
  delete-filters                    Filters API is deprecated
```

## Appendix C: Key Documentation References

The following docs in `docs/` contain the authoritative API reference for the new Rulesets API:

| Doc File | Covers |
|---|---|
| `docs/cf-api-rulesets.md` | Complete Rulesets API reference — list, get, create, update, delete operations |
| `docs/cf-add-rules-to-a-custom-ruleset.md` | Adding/updating rules in a custom ruleset (PUT bulk replace) |
| `docs/cf-deploy-a-custom-ruleset.md` | Deploying a custom ruleset with `execute` action at account/zone level |
| `docs/cf-firewall-rules-upgrade.md` | Migration guide from Firewall Rules to WAF custom rules (Skip action, etc.) |
| `docs/cf-ruleset-api-readme.md` | Creating custom rules via API with examples (challenge, block, custom responses) |
