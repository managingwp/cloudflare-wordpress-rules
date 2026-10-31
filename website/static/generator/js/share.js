// Share links and stored state.
//
// Two payload shapes exist in the wild:
//
//   v1  { p, v, o }            — a preset name plus the option form
//   v2  { k, n, v, o, m }      — the source (builder/release), the options, and
//                                only the hand-edited rules, because everything
//                                else is derivable from the source
//
// v2 keeps links short in the normal case and still carries an edit: `m` holds
// just the rules the user typed into. A v1 link decodes through the same
// normaliser, so links minted before the editor existed keep working.
//
// No DOM access, so the round trip is testable under Node.

function base64UrlEncode(text) {
  const bytes = new TextEncoder().encode(text);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function base64UrlDecode(value) {
  const padded = value.replace(/-/g, "+").replace(/_/g, "/");
  const binary = atob(padded + "=".repeat((4 - (padded.length % 4)) % 4));
  return new TextDecoder().decode(Uint8Array.from(binary, (character) => character.charCodeAt(0)));
}

export function encodePayload(payload) {
  return base64UrlEncode(JSON.stringify(payload));
}

export function decodePayload(value) {
  try {
    const parsed = JSON.parse(base64UrlDecode(String(value)));
    return parsed && typeof parsed === "object" ? parsed : null;
  } catch {
    return null;
  }
}

/** The hand-edited rules, in the compact shape a link carries. */
export function manualRulesFor(rules) {
  return (Array.isArray(rules) ? rules : [])
    .filter((rule) => rule && rule.origin === "manual")
    .map((rule) => {
      const entry = {
        ref: String(rule.ref),
        action: String(rule.action || "block"),
        enabled: rule.enabled !== false,
        logging: rule.logging !== false,
        expression: String(rule.expression ?? ""),
      };
      if (rule.action === "skip" && rule.actionParameters) {
        entry.ap = rule.actionParameters;
      }
      return entry;
    });
}

/** Entries carried by a link, tolerated to be missing optional fields. */
export function normalizeManualEntries(list) {
  return (Array.isArray(list) ? list : [])
    .filter((entry) => entry
      && typeof entry === "object"
      && typeof entry.ref === "string"
      && entry.ref.startsWith("lmt-"))
    .map((entry) => {
      const normalized = {
        ref: entry.ref,
        action: typeof entry.action === "string" && entry.action ? entry.action : "block",
        enabled: entry.enabled !== false,
        logging: entry.logging !== false,
        expression: String(entry.expression ?? ""),
      };
      if (entry.ap && typeof entry.ap === "object") normalized.ap = entry.ap;
      return normalized;
    });
}

/**
 * Normalise a decoded link (or stored payload) to one shape. Returns null when
 * there is nothing usable in it.
 */
export function readShareState(parsed) {
  if (!parsed || typeof parsed !== "object") return null;

  let kind = "";
  if (parsed.k === "release" || parsed.k === "builder") kind = parsed.k;
  else if (!Object.hasOwn(parsed, "k") && typeof parsed.p === "string") kind = "builder";
  const name = typeof parsed.n === "string"
    ? parsed.n
    : (typeof parsed.p === "string" ? parsed.p : "");

  const options = parsed.o && typeof parsed.o === "object" ? parsed.o : null;
  const version = typeof parsed.v === "string" || typeof parsed.v === "number" ? String(parsed.v) : "";
  const manual = normalizeManualEntries(parsed.m);

  if (!name && !options && manual.length === 0) return null;
  if (!kind) return null;

  return { kind, name, version, options, manual };
}
