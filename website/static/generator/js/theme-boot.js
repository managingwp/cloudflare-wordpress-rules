// Resolves the stored colour-theme preference before the first paint.
//
// This file is deliberately a classic (non-module) script loaded from <head>:
// module scripts are deferred, so resolving the palette there would paint the
// light theme first on a dark page. The switch itself lives in js/theme.js —
// keep the storage key and the preference values in sync with that module.

(function () {
  var key = "cfwpr.generator.theme.v1";
  var preference = "auto";

  try {
    var stored = window.localStorage.getItem(key);
    if (stored === "auto" || stored === "light" || stored === "dark") preference = stored;
  } catch (error) {
    // Storage blocked (private mode, file://): follow the operating system.
  }

  var prefersDark = typeof window.matchMedia === "function"
    && window.matchMedia("(prefers-color-scheme: dark)").matches;
  var dark = preference === "dark" || (preference === "auto" && prefersDark);

  document.documentElement.setAttribute("data-theme", dark ? "dark" : "light");
  document.documentElement.setAttribute("data-theme-preference", preference);
})();
