// UI wiring. Everything stays in this tab: no requests except the preset
// files served alongside this page, no analytics, no credentials.

import {
  DEFAULT_OPTIONS,
  DEFAULT_TEMPLATE_VERSION,
  buildRules,
  isValidTemplateVersion,
  mergeOptions,
  normalizeOptions,
  splitList,
  validateOptions,
} from "./rules.js";
import { builtinPreset, exportPreset, importPreset, loadPresets } from "./presets.js";
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

const state = {
  presets: [],
  presetName: "custom",
  preset: null,
  options: normalizeOptions(DEFAULT_OPTIONS),
  templateVersion: DEFAULT_TEMPLATE_VERSION,
  edited: false,
};

let countries = [];
let rules = [];
let hashTimer = null;

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
    p: state.presetName,
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
  const payload = { p: state.presetName, v: state.templateVersion, o: state.options };
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
  el("opt-version").value = state.templateVersion;
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
  renderPresetTabs();
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

// -- presets ---------------------------------------------------------------

function renderPresetTabs() {
  const container = el("preset-tabs");
  container.textContent = "";
  for (const preset of state.presets) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "btn";
    button.textContent = preset.label || preset.name;
    const active = preset.name === state.presetName && !state.edited;
    button.setAttribute("aria-pressed", active ? "true" : "false");
    button.addEventListener("click", () => {
      if (state.edited && !window.confirm(`Discard your edits and load "${preset.label || preset.name}"?`)) {
        return;
      }
      applyPreset(preset);
    });
    container.append(button);
  }
  const custom = document.createElement("button");
  custom.type = "button";
  custom.className = "btn";
  custom.textContent = "Custom";
  custom.setAttribute("aria-pressed", state.edited ? "true" : "false");
  custom.disabled = true;
  container.append(custom);
}

function applyPreset(preset, saved) {
  state.preset = preset;
  state.presetName = preset.name;
  state.edited = false;
  state.templateVersion = saved && saved.v ? String(saved.v) : preset.templateVersion;
  state.options = saved && saved.o
    ? normalizeOptions(mergeOptions(preset.options || DEFAULT_OPTIONS, saved.o))
    : normalizeOptions(preset.options || DEFAULT_OPTIONS);
  el("preset-description").textContent = preset.description || "";
  writeForm();
  update();
}

// -- rendering -------------------------------------------------------------

function messageItem(text, tone) {
  const item = document.createElement("li");
  item.className = tone;
  item.textContent = text;
  return item;
}

function renderMessages(validation, limits) {
  const list = el("messages");
  list.textContent = "";

  for (const error of validation.errors) list.append(messageItem(error.message, "error"));
  for (const warning of validation.warnings) list.append(messageItem(warning.message, "warn"));

  if (!isValidTemplateVersion(state.templateVersion)) {
    list.append(messageItem('Template version must be a rules version such as "207" or "beta".', "error"));
  }
  if (limits.rulesOver) {
    list.append(messageItem(
      `Free plan allows ${limits.maxRules} custom rules; this set uses ${limits.rules}.`,
      "error",
    ));
  }
  for (const item of limits.perRule) {
    if (item.over) {
      list.append(messageItem(
        `${item.ref} is ${item.chars} characters, over the ${limits.maxChars} limit. Use an IP list or split the rule.`,
        "error",
      ));
    } else if (item.near) {
      list.append(messageItem(
        `${item.ref} is at ${item.chars} of ${limits.maxChars} characters.`,
        "warn",
      ));
    }
  }

  if (rules.length === 0) {
    list.append(messageItem("No rules yet: enable a challenge or add a trusted source.", "ok"));
  } else if (list.children.length === 0) {
    list.append(messageItem("All rules fit within the Free plan limits.", "ok"));
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

  rules.forEach((rule, index) => {
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
    const text = rules
      .map((rule) => `# ${rule.ref} — ${rule.action}\n${rule.expression}`)
      .join("\n\n");
    copyText(text, copyAll);
  });
  all.append(copyAll);
  container.append(all);
}

function renderApi() {
  const body = toApiBody(rules, state.templateVersion);
  const manifest = toManifest(rules, state.templateVersion);
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
  const base = state.preset && !state.preset.builtin ? state.preset.name : slugify(state.presetName);
  return `${slugify(base)}-generated`;
}

function renderProfile() {
  const name = profileName();
  const profile = toV3Profile(
    name,
    (state.preset && state.preset.description) || "Generated with the Cloudflare WAF rule generator",
    rules,
    state.templateVersion,
  );
  const json = JSON.stringify(profile, null, 2);
  el("profile-name").textContent = `profiles/${name}.json`;
  el("profile-json").textContent = json;
  el("copy-profile").onclick = (event) => copyText(json, event.currentTarget);
  el("download-profile").onclick = () => download(`${name}.json`, json);
}

function update(fromForm = false) {
  if (fromForm) {
    state.options = readForm();
    state.edited = true;
  }
  state.templateVersion = el("opt-version").value.trim() || DEFAULT_TEMPLATE_VERSION;

  const validation = validateOptions(state.options);
  state.options = validation.options;
  rules = buildRules(state.options);
  const limits = summarizeLimits(rules);

  el("ips-count").textContent = String(state.options.trustedIps.inline.length);
  el("rules-used").textContent = `${limits.rules} / ${MAX_CUSTOM_RULES}`;
  el("rules-progress").max = MAX_CUSTOM_RULES;
  el("rules-progress").value = Math.min(limits.rules, MAX_CUSTOM_RULES);
  el("rules-progress").setAttribute("aria-valuetext", `${limits.rules} of ${MAX_CUSTOM_RULES} rules`);

  renderMessages(validation, limits);
  renderRuleCards(limits);
  renderApi();
  renderProfile();
  renderPresetTabs();
  persist();
}

// -- tabs ------------------------------------------------------------------

function selectTab(tab) {
  const tabs = [...document.querySelectorAll('[role="tab"]')];
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
  const tabs = [...document.querySelectorAll('[role="tab"]')];
  for (const tab of tabs) {
    tab.addEventListener("click", () => selectTab(tab));
    tab.addEventListener("keydown", (event) => {
      if (event.key !== "ArrowRight" && event.key !== "ArrowLeft") return;
      event.preventDefault();
      const index = tabs.indexOf(tab);
      const next = event.key === "ArrowRight"
        ? tabs[(index + 1) % tabs.length]
        : tabs[(index - 1 + tabs.length) % tabs.length];
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
    "opt-version", "opt-geo-action",
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

  el("country-add").addEventListener("click", () => addCountry(el("country-input").value));
  el("country-input").addEventListener("keydown", (event) => {
    if (event.key !== "Enter") return;
    event.preventDefault();
    addCountry(el("country-input").value);
  });
  el("country-input").addEventListener("change", () => addCountry(el("country-input").value));

  el("reset").addEventListener("click", () => {
    const preset = state.presets.find((item) => item.name === state.presetName);
    applyPreset(preset || builtinPreset());
  });

  el("share").addEventListener("click", (event) => {
    window.history.replaceState(null, "", `#s=${encodeState()}`);
    copyText(window.location.href, event.currentTarget, "Link copied");
  });

  el("preset-export").addEventListener("click", () => {
    const name = slugify(state.presetName);
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
      applyPreset(preset);
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
  fillCountryDatalist();
  bindTabs();
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

  const saved = readHash() || readStorage();
  const initial = (saved && presets.find((preset) => preset.name === saved.p)) || presets[0];
  state.presets = presets;
  applyPreset(initial, saved);
  renderUaSuggestionChips();
}

init();
