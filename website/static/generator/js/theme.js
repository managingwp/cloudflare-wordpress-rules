// Colour-theme switch: Auto (follow the operating system), Light, Dark.
//
// The palette is chosen by data-theme on <html>. The pre-paint half lives in
// js/theme-boot.js, which is a classic script so it can run before the first
// paint; keep the storage key and the preference values in sync with it.

const STORAGE_KEY = "cfwpr.generator.theme.v1";
export const THEME_PREFERENCES = ["auto", "light", "dark"];

// Pure helper, so the resolution rule is testable outside the browser.
export function resolveTheme(preference, systemPrefersDark) {
  if (preference === "light" || preference === "dark") return preference;
  return systemPrefersDark ? "dark" : "light";
}

function systemPrefersDark() {
  return typeof window.matchMedia === "function"
    && window.matchMedia("(prefers-color-scheme: dark)").matches;
}

function readPreference() {
  try {
    const stored = window.localStorage.getItem(STORAGE_KEY);
    if (THEME_PREFERENCES.includes(stored)) return stored;
  } catch (error) {
    // Storage blocked: fall back to following the operating system.
  }
  return "auto";
}

function writePreference(preference) {
  try {
    window.localStorage.setItem(STORAGE_KEY, preference);
  } catch (error) {
    // Not saved: the choice still applies to this page view.
  }
}

function apply(preference) {
  const root = document.documentElement;
  root.setAttribute("data-theme", resolveTheme(preference, systemPrefersDark()));
  root.setAttribute("data-theme-preference", preference);
  for (const button of document.querySelectorAll("[data-theme-value]")) {
    button.setAttribute("aria-pressed", button.dataset.themeValue === preference ? "true" : "false");
  }
}

export function initTheme() {
  apply(readPreference());

  for (const button of document.querySelectorAll("[data-theme-value]")) {
    button.addEventListener("click", () => {
      const preference = button.dataset.themeValue;
      if (!THEME_PREFERENCES.includes(preference)) return;
      writePreference(preference);
      apply(preference);
    });
  }

  const query = typeof window.matchMedia === "function"
    ? window.matchMedia("(prefers-color-scheme: dark)")
    : null;
  if (query && typeof query.addEventListener === "function") {
    query.addEventListener("change", () => {
      // Only "Auto" tracks the operating system; an explicit choice stays put.
      if (readPreference() === "auto") apply("auto");
    });
  }
}
