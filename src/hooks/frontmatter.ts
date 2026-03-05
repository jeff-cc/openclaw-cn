import JSON5 from "json5";

import { parseFrontmatterBlock } from "../markdown/frontmatter.js";
import { parseBooleanValue } from "../utils/boolean.js";
import type {
  OpenclawHookMetadata,
  HookEntry,
  HookInstallSpec,
  HookInvocationPolicy,
  ParsedHookFrontmatter,
} from "./types.js";

export function parseFrontmatter(content: string): ParsedHookFrontmatter {
  return parseFrontmatterBlock(content);
}

function normalizeStringList(input: unknown): string[] {
  if (!input) return [];
  if (Array.isArray(input)) {
    return input.map((value) => String(value).trim()).filter(Boolean);
  }
  if (typeof input === "string") {
    return input
      .split(",")
      .map((value) => value.trim())
      .filter(Boolean);
  }
  return [];
}

function parseInstallSpec(input: unknown): HookInstallSpec | undefined {
  if (!input || typeof input !== "object") return undefined;
  const raw = input as Record<string, unknown>;
  const kindRaw =
    typeof raw.kind === "string" ? raw.kind : typeof raw.type === "string" ? raw.type : "";
  const kind = kindRaw.trim().toLowerCase();
  if (kind !== "bundled" && kind !== "npm" && kind !== "git") {
    return undefined;
  }

  const spec: HookInstallSpec = {
    kind: kind as HookInstallSpec["kind"],
  };

  if (typeof raw.id === "string") spec.id = raw.id;
  if (typeof raw.label === "string") spec.label = raw.label;
  const bins = normalizeStringList(raw.bins);
  if (bins.length > 0) spec.bins = bins;
  if (typeof raw.package === "string") spec.package = raw.package;
  if (typeof raw.repository === "string") spec.repository = raw.repository;

  return spec;
}

function getFrontmatterValue(frontmatter: ParsedHookFrontmatter, key: string): string | undefined {
  const raw = frontmatter[key];
  return typeof raw === "string" ? raw : undefined;
}

function parseFrontmatterBool(value: string | undefined, fallback: boolean): boolean {
  const parsed = parseBooleanValue(value);
  return parsed === undefined ? fallback : parsed;
}

export function resolveOpenclawMetadata(
  frontmatter: ParsedHookFrontmatter,
): OpenclawHookMetadata | undefined {
  const raw = getFrontmatterValue(frontmatter, "metadata");
  if (!raw) return undefined;
  try {
    const parsed = JSON5.parse(raw) as { openclaw?: unknown; clawdbot?: unknown };
    if (!parsed || typeof parsed !== "object") return undefined;
    // Support legacy "clawdbot" key for backward compatibility with older hooks
    const openclaw =
      (parsed as { openclaw?: unknown; clawdbot?: unknown }).openclaw ??
      (parsed as { clawdbot?: unknown }).clawdbot;
    if (!openclaw || typeof openclaw !== "object") return undefined;
    const openclawObj = openclaw as Record<string, unknown>;
    const requiresRaw =
      typeof openclawObj.requires === "object" && openclawObj.requires !== null
        ? (openclawObj.requires as Record<string, unknown>)
        : undefined;
    const installRaw = Array.isArray(openclawObj.install) ? (openclawObj.install as unknown[]) : [];
    const install = installRaw
      .map((entry) => parseInstallSpec(entry))
      .filter((entry): entry is HookInstallSpec => Boolean(entry));
    const osRaw = normalizeStringList(openclawObj.os);
    const eventsRaw = normalizeStringList(openclawObj.events);
    return {
      always: typeof openclawObj.always === "boolean" ? openclawObj.always : undefined,
      emoji: typeof openclawObj.emoji === "string" ? openclawObj.emoji : undefined,
      homepage: typeof openclawObj.homepage === "string" ? openclawObj.homepage : undefined,
      hookKey: typeof openclawObj.hookKey === "string" ? openclawObj.hookKey : undefined,
      export: typeof openclawObj.export === "string" ? openclawObj.export : undefined,
      os: osRaw.length > 0 ? osRaw : undefined,
      events: eventsRaw.length > 0 ? eventsRaw : [],
      requires: requiresRaw
        ? {
            bins: normalizeStringList(requiresRaw.bins),
            anyBins: normalizeStringList(requiresRaw.anyBins),
            env: normalizeStringList(requiresRaw.env),
            config: normalizeStringList(requiresRaw.config),
          }
        : undefined,
      install: install.length > 0 ? install : undefined,
    };
  } catch {
    return undefined;
  }
}

/** @deprecated Use resolveOpenclawMetadata instead */
export const resolveClawdbotMetadata = resolveOpenclawMetadata;

export function resolveHookInvocationPolicy(
  frontmatter: ParsedHookFrontmatter,
): HookInvocationPolicy {
  return {
    enabled: parseFrontmatterBool(getFrontmatterValue(frontmatter, "enabled"), true),
  };
}

export function resolveHookKey(hookName: string, entry?: HookEntry): string {
  return entry?.openclaw?.hookKey ?? hookName;
}
