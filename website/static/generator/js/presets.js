// Preset loading, `extends` resolution, and local import/export.
//
// Presets live next to the app in profiles/*.json and are listed in
// profiles/index.json. Loading is same-origin only; if fetch is unavailable
// (file://), the app falls back to the built-in defaults and says so.

import {
  DEFAULT_OPTIONS,
  DEFAULT_TEMPLATE_VERSION,
  isValidTemplateVersion,
  mergeOptions,
  normalizeOptions,
  validateOptions,
} from "./rules.js";

const MANIFEST_URL = new URL("../profiles/index.json", import.meta.url);
const PRESET_KEYS = ["name", "label", "description", "templateVersion", "extends", "options"];
const MAX_EXTENDS_DEPTH = 5;

async function fetchJson(url) {
  const response = await fetch(url, { cache: "no-store" });
  if (!response.ok) {
    throw new Error(`Could not load ${url}: HTTP ${response.status}`);
  }
  return response.json();
}

export function builtinPreset() {
  return {
    name: "custom",
    label: "Custom",
    description: "Built-in defaults (presets could not be loaded)",
    templateVersion: DEFAULT_TEMPLATE_VERSION,
    extends: null,
    options: normalizeOptions(DEFAULT_OPTIONS),
    builtin: true,
  };
}

/** Structural validation for a preset object from the repo or a file import. */
export function checkPreset(raw, sourceName = "") {
  const errors = [];
  const warnings = [];

  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    return { errors: [`${sourceName || "preset"}: not a JSON object`], warnings };
  }
  const name = String(raw.name || sourceName || "").trim();
  if (!/^[a-z0-9][a-z0-9-]{0,63}$/.test(name)) {
    errors.push(`${sourceName || "preset"}: "name" must be a lowercase slug`);
  }
  if (typeof raw.label !== "string" || raw.label.trim() === "") {
    errors.push(`${name}: "label" is required`);
  }
  if (!raw.options || typeof raw.options !== "object" || Array.isArray(raw.options)) {
    errors.push(`${name}: "options" object is required`);
  }
  const templateVersion = raw.templateVersion === undefined
    ? DEFAULT_TEMPLATE_VERSION
    : String(raw.templateVersion);
  if (!isValidTemplateVersion(templateVersion)) {
    errors.push(`${name}: "templateVersion" must be a rules version such as "207"`);
  }
  if (raw.extends !== undefined && raw.extends !== null && typeof raw.extends !== "string") {
    errors.push(`${name}: "extends" must be a preset name or null`);
  }
  for (const key of Object.keys(raw)) {
    if (!PRESET_KEYS.includes(key)) warnings.push(`${name}: unknown preset key "${key}" ignored`);
  }
  if (raw.options && typeof raw.options === "object") {
    for (const key of Object.keys(raw.options)) {
      if (!(key in DEFAULT_OPTIONS)) warnings.push(`${name}: unknown option "${key}" ignored`);
    }
  }

  const preset = {
    name,
    label: String(raw.label || name),
    description: String(raw.description || ""),
    templateVersion,
    extends: raw.extends || null,
    options: raw.options && typeof raw.options === "object" ? raw.options : {},
  };

  return { preset, errors, warnings };
}

function resolveOne(preset, byName, seen) {
  if (!preset.extends) {
    return { ...preset, options: normalizeOptions(preset.options) };
  }
  if (seen.includes(preset.name)) {
    throw new Error(`Preset extends cycle: ${[...seen, preset.name].join(" -> ")}`);
  }
  const parent = byName.get(preset.extends);
  if (!parent) {
    throw new Error(`Preset "${preset.name}" extends unknown preset "${preset.extends}"`);
  }
  if (seen.length >= MAX_EXTENDS_DEPTH) {
    throw new Error(`Preset extends chain too deep at "${preset.name}"`);
  }
  const resolvedParent = resolveOne(parent, byName, [...seen, preset.name]);
  return {
    ...preset,
    label: preset.label || resolvedParent.label,
    templateVersion: preset.templateVersion || resolvedParent.templateVersion,
    options: normalizeOptions(mergeOptions(resolvedParent.options, preset.options)),
  };
}

/** Resolve `extends` for a list of presets (order preserved). */
export function resolvePresets(presets) {
  const byName = new Map(presets.map((preset) => [preset.name, preset]));
  return presets.map((preset) => resolveOne(preset, byName, []));
}

/**
 * Load profiles/index.json plus every preset it lists.
 * Throws on network failure — the caller decides whether to fall back.
 */
export async function loadPresets(manifestUrl = MANIFEST_URL) {
  const manifest = await fetchJson(manifestUrl);
  const names = Array.isArray(manifest) ? manifest : manifest.presets;
  if (!Array.isArray(names) || names.length === 0) {
    throw new Error("profiles/index.json must list at least one preset");
  }

  const loaded = [];
  const warnings = [];
  for (const name of names) {
    const url = new URL(`../profiles/${name}.json`, manifestUrl);
    const raw = await fetchJson(url);
    const checked = checkPreset(raw, name);
    if (checked.errors.length > 0) {
      throw new Error(checked.errors.join("; "));
    }
    warnings.push(...checked.warnings);
    loaded.push(checked.preset);
  }

  return { presets: resolvePresets(loaded), warnings };
}

/** Validate a user-imported preset object before it becomes a tab. */
export function importPreset(raw, fallbackName = "imported") {
  const sourceName = raw && typeof raw.name === "string" ? raw.name : fallbackName;
  const checked = checkPreset(raw, sourceName);
  if (checked.errors.length > 0) {
    throw new Error(checked.errors.join("; "));
  }
  return {
    preset: { ...checked.preset, name: `${checked.preset.name}-imported`, imported: true },
    warnings: checked.warnings,
  };
}

export function exportPreset(preset) {
  return JSON.stringify(
    {
      name: preset.name,
      label: preset.label,
      description: preset.description,
      templateVersion: preset.templateVersion,
      extends: preset.extends || null,
      options: preset.options,
    },
    null,
    2,
  );
}

/** Convenience wrapper used by the UI: resolve, then validate the options. */
export function preparePreset(preset) {
  const options = normalizeOptions(preset.options || {});
  const validation = validateOptions(options);
  return { ...preset, options: validation.options, validation };
}
