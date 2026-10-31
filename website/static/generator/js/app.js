// UI wiring. Everything stays in this tab: no requests except the preset and
// versions files served alongside this page, no analytics, no credentials.

import {
  DEFAULT_OPTIONS,
  DEFAULT_TEMPLATE_VERSION,
  isValidTemplateVersion,
  mergeOptions,
  normalizeOptions,
  splitList,
  validateOptions,
} from "./rules.js";
import { rulesFromOptions, rulesFromProfile, versionFor } from "./ruleset.js";
import { builtinPreset, exportPreset, importPreset, loadPresets } from "./presets.js";
import { describeVersion, findVersion, loadVersions } from "./versions.js";
import {
  UPGRADE_RULES,
  entrypointUrl,
  ruleDescription,
  slugify,
  toApiBody,
  toCurl,
  toManifest,
  toV3Profile,
} from "./format.js";
import { MAX_CUSTOM_RULES, MAX_EXPRESSION_CHARS, summarizeLimits } from "./limits.js";
import { ISO_COUNTRIES, countryName } from "./countries.js";
import { initTheme } from "./theme.js";

const STORAGE_KEY = "cfwpr.generator.options.v1";
const UA_SUGGESTIONS = [
  "PerplexityBot",
  "Perplexity-User",
  "GPTBot",
  "OAI-SearchBot",
  "ClaudeBot",
  "CCBot",
  "Googlebot",
  "Bingbot",
  "Uptime-Kuma",
  "Better Uptime Bot",
  "Wordfence Central API",
  "WPUmbrella",
  "Stripe/",
  "PayPal IPN",
];

const STEPS = [
  { id: "step-start", tab: "tab-start", label: "Start", next: "Trusted traffic" },
  { id: "step-trusted", tab: "tab-trusted", label: "Trusted traffic", next: "Blocking" },
  { id: "step-blocking", tab: "tab-blocking", label: "Blocking", next: "Challenges" },
  { id: "step-challenges", tab: "tab-challenges", label: "Challenges", next: "Output" },
  { id: "step-output", tab: "tab-output", label: "Output", next: null },
];

const STEP_FOR_REF = {
  "lmt-r1": "step-trusted",
  "lmt-r2": "step-blocking",
  "lmt-r3": "step-challenges",
  "lmt-r4": "step-challenges",
};

const STEP_FOR_PATH = [
  [/^(trustedIps|allowedQueryStrings|allowedUserAgents|allowVerifiedBots|allowTwoFactorActions)/, "step-trusted"],
  [/^(blockedPaths|blockXmlrpc|blockedAsns)/, "step-blocking"],
  [/^(challengeLoginAdmin|geo)/, "step-challenges"],
];

const FIELDSETS = ["fields-trusted", "fields-blocking", "fields-challenges"];

const state = {
  presets: [],
  versions: [],
  source: { kind: "builder", name: "default" },
  preset: null,
  options: normalizeOptions(DEFAULT_OPTIONS),
  rules: [],
  templateVersion: DEFAULT_TEMPLATE_VERSION,
  edited: false,
  step: 0,
};

let countries = [];
let hashTimer = null;
let lastMessageSignature = null;

const el = (id) => document.getElementById(id);

// -- generic helpers -------------------------------------------------------

function flash(button, label = "Copied") {
  if (!button) return;
  const original = button.dataset.label || button.textContent;
  button.dataset.label = original;
  button.textContent = label;
  button.classList.add("flash");
  setTimeout(() => {
    button.textContent = original;
    button.classList.remove("flash");
  }, 1500);
}

async function copyText(text, button, label) {
  try {
    await navigator.clipboard.writeText(text);
  } catch {
    const helper = document.createElement("textarea");
    helper.value = text;
    helper.setAttribute("readonly", "");
    helper.className = "sr-only";
    document.body.append(helper);
    helper.select();
    try {
      document.execCommand("copy");
    } finally {
      helper.remove();
    }
  }
  flash(button, label);
}

function download(filename, text, type = "application/json") {
  const blob = new Blob([text], { type });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  document.body.append(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

function showNotice(message) {
  const notice = el("notice");
  notice.textContent = message;
  notice.hidden = false;
}

function encodeState() {
  const payload = {
    k: state.source.kind,
    n: state.source.name,
    v: state.templateVersion,
    o: state.options,
  };
  const bytes = new TextEncoder().encode(JSON.stringify(payload));
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function decodeState(value) {
  try {
    const padded = value.replace(/-/g, "+").replace(/_/g, "/");
    const binary = atob(padded + "=".repeat((4 - (padded.length % 4)) % 4));
    const bytes = Uint8Array.from(binary, (char) => char.charCodeAt(0));
    const parsed = JSON.parse(new TextDecoder().decode(bytes));
    if (!parsed || typeof parsed !== "object") return null;
    return parsed;
  } catch {
    return null;
  }
}

function readHash() {
  const match = /^#s=(.+)$/.exec(window.location.hash);
  return match ? decodeState(match[1]) : null;
}

function readStorage() {
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    return raw ? JSON.parse(raw) : null;
  } catch {
    return null;
  }
}

function persist() {
  const payload = {
    k: state.source.kind,
    n: state.source.name,
    v: state.templateVersion,
    o: state.options,
  };
  try {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(payload));
    el("storage-note").textContent = "Saved in this browser";
  } catch {
    el("storage-note").textContent = "Not saved (storage blocked)";
  }

  clearTimeout(hashTimer);
  hashTimer = setTimeout(() => {
    const next = `#s=${encodeState()}`;
    if (window.location.hash !== next) {
      window.history.replaceState(null, "", next);
    }
  }, 250);
}

// -- steps -----------------------------------------------------------------

function stepIndexById(id) {
  return STEPS.findIndex((step) => step.id === id);
}

function showStep(index, { focus = true } = {}) {
  const clamped = Math.max(0, Math.min(index, STEPS.length - 1));
  state.step = clamped;

  STEPS.forEach((step, position) => {
    const tab = el(step.tab);
    const panel = el(step.id);
    const selected = position === clamped;
    tab.setAttribute("aria-selected", selected ? "true" : "false");
    tab.tabIndex = selected ? 0 : -1;
    panel.hidden = !selected;
  });

  const current = STEPS[clamped];
  el("step-position").textContent = `Step ${clamped + 1} of ${STEPS.length}`;
  el("step-back").disabled = clamped === 0;
  el("step-next").hidden = !current.next;
  if (current.next) el("step-next").textContent = `Next: ${current.next} →`;
  el("step-announcer").textContent = `Step ${clamped + 1} of ${STEPS.length}: ${current.label}`;

  if (focus) {
    const panel = el(current.id);
    const title = panel.querySelector(".step-title") || panel;
    title.focus();
  }
}

function bindSteps() {
  const tabs = STEPS.map((step) => el(step.tab));
  tabs.forEach((tab, index) => {
    tab.addEventListener("click", () => showStep(index));
    tab.addEventListener("keydown", (event) => {
      const keys = {
        ArrowRight: (index + 1) % tabs.length,
        ArrowLeft: (index - 1 + tabs.length) % tabs.length,
        Home: 0,
        End: tabs.length - 1,
      };
      if (!(event.key in keys)) return;
      event.preventDefault();
      showStep(keys[event.key]);
      tabs[keys[event.key]].focus();
    });
  });

  el("step-back").addEventListener("click", () => showStep(state.step - 1));
  el("step-next").addEventListener("click", () => showStep(state.step + 1));
  el("status-issues").addEventListener("click", () => {
    const target = el("status-issues").dataset.step;
    if (target) showStep(stepIndexById(target));
    else showStep(STEPS.length - 1);
  });
}

// -- form ------------------------------------------------------------------

function writeCountryChips() {
  const container = el("country-chips");
  container.textContent = "";
  for (const code of countries) {
    const chip = document.createElement("span");
    chip.className = "chip";
    const label = document.createElement("span");
    label.textContent = code;
    label.title = countryName(code);
    const remove = document.createElement("button");
    remove.type = "button";
    remove.textContent = "×";
    remove.setAttribute("aria-label", `Remove ${code}`);
    remove.addEventListener("click", () => {
      countries = countries.filter((item) => item !== code);
      writeCountryChips();
      update(true);
    });
    chip.append(label, remove);
    container.append(chip);
  }
}

function addCountry(raw) {
  const code = String(raw || "").trim().toUpperCase();
  if (!/^[A-Z]{2}$/.test(code)) return false;
  if (!countries.includes(code)) {
    countries = [...countries, code].sort();
    writeCountryChips();
    update(true);
  }
  el("country-input").value = "";
  return true;
}

function writeForm() {
  const options = state.options;
  el("opt-ips").value = options.trustedIps.inline.join("\n");
  el("opt-ip-list").checked = options.trustedIps.ipList.enabled;
  el("opt-ip-list-name").value = options.trustedIps.ipList.name;
  el("opt-queries").value = options.allowedQueryStrings.join("\n");
  el("opt-uas").value = options.allowedUserAgents.join("\n");
  el("opt-paths").value = options.blockedPaths.join("\n");
  el("opt-asns").value = options.blockedAsns.join("\n");
  el("opt-xmlrpc").checked = options.blockXmlrpc;
  el("opt-login").checked = options.challengeLoginAdmin;
  el("opt-geo-enabled").checked = options.geo.enabled;
  el("opt-geo-action").value = options.geo.action;
  el("opt-verified-bots").checked = options.allowVerifiedBots;
  el("opt-2fa").checked = options.allowTwoFactorActions;
  countries = [...options.geo.allowedCountries];
  writeCountryChips();
  renderUaSuggestionChips();
}

function readForm() {
  return normalizeOptions({
    trustedIps: {
      inline: splitList(el("opt-ips").value),
      ipList: { enabled: el("opt-ip-list").checked, name: el("opt-ip-list-name").value },
    },
    allowedQueryStrings: splitList(el("opt-queries").value),
    allowedUserAgents: splitList(el("opt-uas").value),
    allowVerifiedBots: el("opt-verified-bots").checked,
    allowTwoFactorActions: el("opt-2fa").checked,
    blockedPaths: splitList(el("opt-paths").value),
    blockXmlrpc: el("opt-xmlrpc").checked,
    blockedAsns: splitList(el("opt-asns").value),
    challengeLoginAdmin: el("opt-login").checked,
    geo: {
      enabled: el("opt-geo-enabled").checked,
      action: el("opt-geo-action").value,
      allowedCountries: countries,
    },
  });
}

// -- sources ---------------------------------------------------------------

function renderSourceOptions() {
  const select = el("opt-source");
  select.textContent = "";

  const builderGroup = document.createElement("optgroup");
  builderGroup.label = "Builder rule sets";
  for (const preset of state.presets) {
    const option = document.createElement("option");
    option.value = `builder:${preset.name}`;
    option.textContent = `${preset.label || preset.name} (builder, v${preset.templateVersion})`;
    builderGroup.append(option);
  }
  select.append(builderGroup);

  if (state.versions.length > 0) {
    const releaseGroup = document.createElement("optgroup");
    releaseGroup.label = "Exact releases (loaded from profiles/)";
    for (const entry of state.versions) {
      const option = document.createElement("option");
      option.value = `release:${entry.value}`;
      option.textContent = describeVersion(entry);
      releaseGroup.append(option);
    }
    select.append(releaseGroup);
  }

  select.value = `${state.source.kind}:${state.source.name}`;
  if (!select.value && select.options.length > 0) select.value = select.options[0].value;
}

function renderSourceNote() {
  const note = el("source-note");
  if (state.source.kind === "release") {
    const entry = findVersion(state.versions, state.source.name);
    note.textContent = entry
      ? `Loaded ${entry.source}: expressions exactly as released, exported in the current v207 shape.`
      : "";
    return;
  }
  note.textContent = state.preset && state.preset.description
    ? state.preset.description
    : "Rules are rebuilt from the fields in steps 2–4.";
}

function setFieldsLocked(locked) {
  for (const id of FIELDSETS) {
    const fieldset = el(id);
    if (fieldset) fieldset.disabled = locked;
  }
  for (const note of document.querySelectorAll(".locked-note")) note.hidden = !locked;
}

function applySource(kind, name, saved) {
  if (kind === "release") {
    const entry = findVersion(state.versions, name);
    if (!entry) {
      showNotice(`Release “${name}” is not in profiles/versions.json, so the default rule set is shown instead.`);
      return applySource("builder", fallbackPresetName(), saved);
    }
    state.source = { kind: "release", name: entry.value };
    state.preset = null;
    state.templateVersion = versionFor({ rules: entry.rules }, entry.value);
    state.rules = rulesFromProfile(entry);
    state.edited = false;
  } else {
    const preset = state.presets.find((item) => item.name === name) || builtinPreset();
    state.source = { kind: "builder", name: preset.name };
    state.preset = preset;
    state.templateVersion = saved && saved.v ? String(saved.v) : preset.templateVersion;
    state.options = saved && saved.o
      ? normalizeOptions(mergeOptions(preset.options || DEFAULT_OPTIONS, saved.o))
      : normalizeOptions(preset.options || DEFAULT_OPTIONS);
    state.rules = rulesFromOptions(state.options);
    state.edited = false;
  }

  renderSourceOptions();
  renderSourceNote();
  setFieldsLocked(state.source.kind === "release");
  writeForm();
  update();
}

function fallbackPresetName() {
  return state.presets.some((preset) => preset.name === "default")
    ? "default"
    : (state.presets[0] && state.presets[0].name) || "default";
}

// -- rendering -------------------------------------------------------------

function stepForMessage(message) {
  if (message.path) {
    for (const [pattern, step] of STEP_FOR_PATH) {
      if (pattern.test(message.path)) return step;
    }
    return "step-start";
  }
  if (message.ref) return STEP_FOR_REF[message.ref] || "step-output";
  return "step-output";
}

function collectMessages(validation, limits) {
  const items = [];
  const push = (text, tone, step) => items.push({ text, tone, step });

  for (const error of validation.errors) push(error.message, "error", stepForMessage(error));
  for (const warning of validation.warnings) push(warning.message, "warn", stepForMessage(warning));

  if (!isValidTemplateVersion(state.templateVersion)) {
    push('The selected source has no valid rules version stamp; pick another source.', "error", "step-start");
  }
  if (limits.rulesOver) {
    push(
      `Free plan allows ${limits.maxRules} custom rules; this set uses ${limits.rules}.`,
      "error",
      "step-output",
    );
  }
  for (const item of limits.perRule) {
    if (item.over) {
      push(
        `${item.ref} is ${item.chars} characters, over the ${item.maxChars} limit. Use an IP list, split the rule, or edit the expression.`,
        "error",
        STEP_FOR_REF[item.ref] || "step-output",
      );
    } else if (item.near) {
      push(
        `${item.ref} is at ${item.chars} of ${item.maxChars} characters.`,
        "warn",
        STEP_FOR_REF[item.ref] || "step-output",
      );
    }
  }

  if (state.rules.length === 0) {
    push("No rules yet: enable a challenge or add a trusted source.", "ok", "step-output");
  } else if (items.length === 0) {
    push("All rules fit within the Free plan limits.", "ok", "step-output");
  }

  return items;
}

function renderMessages(items) {
  const signature = JSON.stringify(items.map((item) => [item.text, item.tone]));
  if (signature === lastMessageSignature) return;
  lastMessageSignature = signature;

  const list = el("messages");
  list.textContent = "";
  for (const item of items) {
    const entry = document.createElement("li");
    entry.className = item.tone;
    entry.textContent = item.text;
    list.append(entry);
  }
}

function renderStatus(items, limits) {
  el("rules-used").textContent = `${limits.rules} / ${MAX_CUSTOM_RULES}`;
  el("rules-used-badge").textContent = `${limits.rules} / ${MAX_CUSTOM_RULES}`;

  const errors = items.filter((item) => item.tone === "error");
  const warnings = items.filter((item) => item.tone === "warn");
  const button = el("status-issues");
  button.classList.remove("has-issues");

  if (errors.length > 0) {
    const step = stepIndexById(errors[0].step);
    button.textContent = `${errors.length} issue${errors.length === 1 ? "" : "s"} on ${STEPS[step].label}`;
    button.dataset.step = errors[0].step;
    button.classList.add("has-issues");
  } else if (warnings.length > 0) {
    const step = stepIndexById(warnings[0].step);
    button.textContent = `${warnings.length} warning${warnings.length === 1 ? "" : "s"} · ${STEPS[step].label}`;
    button.dataset.step = warnings[0].step;
  } else {
    button.textContent = "No issues";
    delete button.dataset.step;
  }

  const r1 = limits.perRule.find((item) => item.ref === "lmt-r1");
  el("status-chars").textContent = r1
    ? `R1 ${r1.chars} / ${MAX_EXPRESSION_CHARS} chars`
    : `${limits.rules} rule${limits.rules === 1 ? "" : "s"}`;

  for (const step of STEPS) {
    const tab = el(step.tab);
    const hasError = items.some((item) => item.tone === "error" && item.step === step.id);
    const hasWarning = items.some((item) => item.tone === "warn" && item.step === step.id);
    tab.classList.toggle("has-error", hasError);
    tab.classList.toggle("has-warning", hasWarning && !hasError);
  }
}

function ipClauseInfo(rule) {
  if (rule.ref !== "lmt-r1") return null;
  const listMatch = /^\(ip\.src in \$([a-z0-9_]+)\)/.exec(rule.expression);
  if (listMatch) return { label: `list: ${listMatch[1]}` };
  const inline = /^\(ip\.src in \{ (.*?) \}\)/.exec(rule.expression);
  if (inline) {
    const count = inline[1].split(" ").filter(Boolean).length;
    return { label: `${count} IP${count === 1 ? "" : "s"}` };
  }
  return null;
}

function renderRuleCards(limits) {
  const container = el("rule-cards");
  container.textContent = "";

  state.rules.forEach((rule, index) => {
    const stats = limits.perRule[index];
    const card = document.createElement("article");
    card.className = `rule-card${stats.over ? " over" : ""}`;

    const header = document.createElement("header");
    const heading = document.createElement("h3");
    heading.textContent = `R${rule.ruleNumber} — ${rule.label}`;
    const meta = document.createElement("div");
    meta.className = "rule-meta";

    const action = document.createElement("span");
    action.className = "badge";
    action.textContent = rule.action.replace(/_/g, " ");
    const ref = document.createElement("span");
    ref.className = "pill";
    ref.textContent = rule.ref;
    meta.append(action, ref, Object.assign(document.createElement("span"), {
      className: "pill",
      textContent: `${stats.chars} / ${MAX_EXPRESSION_CHARS}`,
    }));
    if (rule.origin === "loaded") {
      meta.append(Object.assign(document.createElement("span"), {
        className: "pill pill-loaded",
        textContent: "loaded",
      }));
    }
    if (rule.origin === "manual") {
      meta.append(Object.assign(document.createElement("span"), {
        className: "pill pill-edited",
        textContent: "edited",
      }));
    }
    const info = ipClauseInfo(rule);
    if (info) {
      meta.append(Object.assign(document.createElement("span"), {
        className: "pill",
        textContent: info.label,
      }));
    }
    header.append(heading, meta);

    const description = document.createElement("p");
    description.className = "hint";
    description.textContent = ruleDescription(rule, state.templateVersion);

    const code = document.createElement("pre");
    code.className = "code";
    code.tabIndex = 0;
    code.textContent = rule.expression;

    const progress = document.createElement("progress");
    progress.max = MAX_EXPRESSION_CHARS;
    progress.value = Math.min(stats.chars, MAX_EXPRESSION_CHARS);
    progress.setAttribute("aria-label", `${rule.ref} characters used`);

    const actions = document.createElement("div");
    actions.className = "card-actions";
    const copy = document.createElement("button");
    copy.type = "button";
    copy.className = "btn";
    copy.textContent = "Copy expression";
    copy.addEventListener("click", () => copyText(rule.expression, copy));
    actions.append(copy, progress);

    card.append(header, description, code, actions);
    container.append(card);
  });

  const all = document.createElement("div");
  all.className = "button-row";
  const copyAll = document.createElement("button");
  copyAll.type = "button";
  copyAll.className = "btn";
  copyAll.textContent = "Copy all expressions";
  copyAll.addEventListener("click", () => {
    const text = state.rules
      .map((rule) => `# ${rule.ref} — ${rule.action}\n${rule.expression}`)
      .join("\n\n");
    copyText(text, copyAll);
  });
  all.append(copyAll);
  container.append(all);
}

function renderApi() {
  const body = toApiBody(state.rules, state.templateVersion);
  const manifest = toManifest(state.rules, state.templateVersion);
  const json = JSON.stringify(body, null, 2);

  el("api-url").textContent = `PUT ${entrypointUrl()}`;
  el("api-json").textContent = json;
  el("api-manifest").textContent = JSON.stringify(manifest, null, 2);
  el("api-curl").textContent = toCurl(body);

  const list = el("upgrade-rules");
  list.textContent = "";
  for (const item of UPGRADE_RULES) {
    const entry = document.createElement("li");
    const match = document.createElement("strong");
    match.textContent = item.match;
    entry.append(match, document.createTextNode(` — ${item.action}`));
    list.append(entry);
  }

  el("copy-api").onclick = (event) => copyText(json, event.currentTarget);
  el("copy-curl").onclick = (event) => copyText(el("api-curl").textContent, event.currentTarget);
  el("download-api").onclick = () => download("ruleset.json", json);
}

function profileName() {
  const base = state.source.kind === "release"
    ? state.source.name
    : (state.preset && !state.preset.builtin ? state.preset.name : slugify(state.source.name));
  return `${slugify(base)}-generated`;
}

function renderProfile() {
  const name = profileName();
  const description = state.source.kind === "release"
    ? `Generated from profiles/ by the Cloudflare WAF rule generator`
    : (state.preset && state.preset.description) || "Generated with the Cloudflare WAF rule generator";
  const profile = toV3Profile(name, description, state.rules, state.templateVersion);
  const json = JSON.stringify(profile, null, 2);
  el("profile-name").textContent = `profiles/${name}.json`;
  el("profile-json").textContent = json;
  el("copy-profile").onclick = (event) => copyText(json, event.currentTarget);
  el("download-profile").onclick = () => download(`${name}.json`, json);
}

function update(fromForm = false) {
  if (fromForm) {
    state.options = readForm();
    if (state.source.kind === "builder") {
      state.rules = rulesFromOptions(state.options);
      state.edited = true;
    }
  }

  const validation = validateOptions(state.options);
  state.options = validation.options;
  if (state.source.kind === "builder") {
    state.rules = rulesFromOptions(state.options);
  }
  const limits = summarizeLimits(state.rules);
  const items = collectMessages(validation, limits);

  el("ips-count").textContent = String(state.options.trustedIps.inline.length);
  el("rules-progress").max = MAX_CUSTOM_RULES;
  el("rules-progress").value = Math.min(limits.rules, MAX_CUSTOM_RULES);
  el("rules-progress").setAttribute("aria-valuetext", `${limits.rules} of ${MAX_CUSTOM_RULES} rules`);

  renderMessages(items);
  renderStatus(items, limits);
  renderRuleCards(limits);
  renderApi();
  renderProfile();
  persist();
}

// -- output tabs -----------------------------------------------------------

function selectTab(tab) {
  const tabs = [...document.querySelectorAll('.tabs [role="tab"]')];
  for (const item of tabs) {
    const selected = item === tab;
    item.setAttribute("aria-selected", selected ? "true" : "false");
    item.tabIndex = selected ? 0 : -1;
    const panel = document.getElementById(item.getAttribute("aria-controls"));
    if (panel) panel.hidden = !selected;
  }
  tab.focus();
}

function bindTabs() {
  const tabs = [...document.querySelectorAll('.tabs [role="tab"]')];
  for (const tab of tabs) {
    tab.addEventListener("click", () => selectTab(tab));
    tab.addEventListener("keydown", (event) => {
      const keys = { ArrowRight: 1, ArrowLeft: -1 };
      if (!(event.key in keys)) return;
      event.preventDefault();
      const index = tabs.indexOf(tab);
      const next = tabs[(index + keys[event.key] + tabs.length) % tabs.length];
      selectTab(next);
    });
  }
}

// -- suggestions -----------------------------------------------------------

function renderUaSuggestionChips() {
  const container = el("ua-suggestions");
  container.textContent = "";
  const current = splitList(el("opt-uas").value);
  for (const suggestion of UA_SUGGESTIONS) {
    const chip = document.createElement("button");
    chip.type = "button";
    chip.className = "chip suggest";
    const added = current.includes(suggestion);
    chip.textContent = added ? `${suggestion} ✓` : `+ ${suggestion}`;
    chip.setAttribute("aria-label", added ? `${suggestion} already allowed` : `Allow ${suggestion}`);
    chip.disabled = added;
    chip.addEventListener("click", () => {
      const values = splitList(el("opt-uas").value);
      values.push(suggestion);
      el("opt-uas").value = values.join("\n");
      renderUaSuggestionChips();
      update(true);
    });
    container.append(chip);
  }
}

function fillCountryDatalist() {
  const list = el("country-options");
  for (const code of ISO_COUNTRIES) {
    const option = document.createElement("option");
    option.value = code;
    option.label = countryName(code);
    list.append(option);
  }
}

// -- events ----------------------------------------------------------------

function bindEvents() {
  for (const id of [
    "opt-ips", "opt-ip-list-name", "opt-queries", "opt-uas", "opt-paths", "opt-asns",
    "opt-geo-action",
  ]) {
    el(id).addEventListener("input", () => update(true));
    el(id).addEventListener("change", () => update(true));
  }
  el("opt-uas").addEventListener("input", renderUaSuggestionChips);
  for (const id of [
    "opt-ip-list", "opt-xmlrpc", "opt-login", "opt-geo-enabled", "opt-verified-bots", "opt-2fa",
  ]) {
    el(id).addEventListener("change", () => update(true));
  }

  el("opt-source").addEventListener("change", (event) => {
    const [kind, ...rest] = event.target.value.split(":");
    applySource(kind, rest.join(":"));
  });

  el("country-add").addEventListener("click", () => addCountry(el("country-input").value));
  el("country-input").addEventListener("keydown", (event) => {
    if (event.key !== "Enter") return;
    event.preventDefault();
    addCountry(el("country-input").value);
  });
  el("country-input").addEventListener("change", () => addCountry(el("country-input").value));

  el("reset").addEventListener("click", () => applySource(state.source.kind, state.source.name));

  el("share").addEventListener("click", (event) => {
    window.history.replaceState(null, "", `#s=${encodeState()}`);
    copyText(window.location.href, event.currentTarget, "Link copied");
  });

  el("preset-export").addEventListener("click", () => {
    const name = slugify(state.source.kind === "release" ? state.source.name : state.source.name);
    download(`${name}.json`, exportPreset({
      name,
      label: (state.preset && state.preset.label) || name,
      description: (state.preset && state.preset.description) || "",
      templateVersion: state.templateVersion,
      extends: null,
      options: state.options,
    }));
  });

  el("preset-import").addEventListener("change", async (event) => {
    const [file] = event.target.files || [];
    if (!file) return;
    try {
      const parsed = JSON.parse(await file.text());
      const { preset } = importPreset(parsed, slugify(file.name.replace(/\.json$/i, "")));
      state.presets = [...state.presets, preset];
      applySource("builder", preset.name);
      showNotice(`Loaded preset "${preset.label}" from ${file.name}. Add it to profiles/index.json to keep it.`);
    } catch (error) {
      showNotice(`Could not load that preset: ${error.message}`);
    } finally {
      event.target.value = "";
    }
  });
}

// -- boot ------------------------------------------------------------------

async function init() {
  initTheme();
  fillCountryDatalist();
  bindTabs();
  bindSteps();
  bindEvents();

  let presets;
  try {
    const loaded = await loadPresets();
    presets = loaded.presets;
    if (loaded.warnings.length > 0) showNotice(loaded.warnings.join(" · "));
    if (!presets.some((preset) => preset.name === "default")) {
      presets = [{ ...builtinPreset(), name: "default", label: "Default" }, ...presets];
    }
  } catch (error) {
    presets = [builtinPreset()];
    showNotice(`Presets could not be loaded (${error.message}). Using built-in defaults — serve this folder over HTTP to load profiles/*.json.`);
  }
  state.presets = presets;

  try {
    const versions = await loadVersions();
    state.versions = versions.versions;
  } catch (error) {
    state.versions = [];
    console.warn(`Release list unavailable: ${error.message}`);
  }

  const saved = readHash() || readStorage();
  const savedKind = saved && typeof saved.k === "string" ? saved.k : (saved && saved.p ? "builder" : "");
  const savedName = saved && typeof saved.n === "string" ? saved.n : (saved && saved.p ? saved.p : "");

  if (savedKind === "release" && findVersion(state.versions, savedName)) {
    applySource("release", savedName, saved);
  } else {
    const builderName = state.presets.some((preset) => preset.name === savedName)
      ? savedName
      : fallbackPresetName();
    applySource("builder", builderName, saved);
  }

  renderUaSuggestionChips();
  showStep(0, { focus: false });
}

init();
