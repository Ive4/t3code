import type { NativeUsageAccount } from './WorkspaceUsageProtocol';

export const DEFAULT_USAGE_WIDGET_TITLE = 'Subscription usage';
export const DEFAULT_USAGE_WIDGET_TTL_MS = 30 * 60 * 1000;
const DEFAULT_MAX_ROWS = 4;

export interface UsageWidgetRow {
  label: string;
  remaining: number;
}

export interface UsageWidgetSnapshot {
  title: string;
  message: string;
  asOf: string;
  rows: UsageWidgetRow[];
  expiresAtMs: number;
}

export interface UsageWidgetSnapshotInput {
  title?: string;
  message?: string;
  emptyMessage?: string;
  asOf?: string;
  rows?: UsageWidgetRow[];
  accounts?: NativeUsageAccount[];
  nowMs?: number;
  expiresAtMs?: number;
  ttlMs?: number;
  maxRows?: number;
}

function clampRemaining(value: number): number {
  if (!Number.isFinite(value)) return 0;
  if (value <= 0) return 0;
  if (value >= 100) return 100;
  return Math.round(value);
}

function normalizeRows(rows: UsageWidgetRow[] | undefined, maxRows: number): UsageWidgetRow[] {
  if (!Array.isArray(rows)) return [];
  const normalized: UsageWidgetRow[] = [];
  for (const row of rows) {
    if (!row || typeof row.label !== 'string') continue;
    const label = row.label.trim();
    if (label.length === 0) continue;
    normalized.push({
      label,
      remaining: clampRemaining(row.remaining),
    });
    if (maxRows > 0 && normalized.length >= maxRows) break;
  }
  return normalized;
}

function deriveRowsFromAccounts(
  accounts: NativeUsageAccount[] | undefined,
  nowMs: number,
  maxRows: number,
): { rows: UsageWidgetRow[]; earliestResetMs?: number } {
  if (!Array.isArray(accounts)) {
    return { rows: [] };
  }
  const rows: UsageWidgetRow[] = [];
  let earliestResetMs: number | undefined;
  for (const account of accounts) {
    if (!account || account.unavailable || !Array.isArray(account.windows)) continue;
    const prefix = typeof account.name === 'string' && account.name.trim().length > 0
      ? account.name.trim()
      : '';
    for (const window of account.windows) {
      if (!window || typeof window.label !== 'string') continue;
      const windowLabel = window.label.trim();
      if (windowLabel.length === 0) continue;
      const label = prefix.length > 0 ? `${prefix} · ${windowLabel}` : windowLabel;
      rows.push({
        label,
        remaining: clampRemaining(window.remainingPercent),
      });
      if (typeof window.resetsAt === 'string' && window.resetsAt.trim().length > 0) {
        const parsed = Date.parse(window.resetsAt);
        if (Number.isFinite(parsed) && parsed > nowMs) {
          earliestResetMs = earliestResetMs === undefined ? parsed : Math.min(earliestResetMs, parsed);
        }
      }
      if (maxRows > 0 && rows.length >= maxRows) {
        return { rows, earliestResetMs };
      }
    }
  }
  return { rows, earliestResetMs };
}

export function formatUsageWidgetSnapshot(input?: UsageWidgetSnapshotInput): UsageWidgetSnapshot {
  const options = input ?? {};
  const nowMs = typeof options.nowMs === 'number' && Number.isFinite(options.nowMs)
    ? options.nowMs
    : Date.now();
  const ttlMs = typeof options.ttlMs === 'number' && Number.isFinite(options.ttlMs) && options.ttlMs > 0
    ? options.ttlMs
    : DEFAULT_USAGE_WIDGET_TTL_MS;
  const maxRows = typeof options.maxRows === 'number' && Number.isFinite(options.maxRows)
    ? Math.floor(options.maxRows)
    : DEFAULT_MAX_ROWS;

  let rows: UsageWidgetRow[] = [];
  let earliestResetMs: number | undefined;
  if (Array.isArray(options.rows)) {
    rows = normalizeRows(options.rows, maxRows);
  } else if (Array.isArray(options.accounts)) {
    const derived = deriveRowsFromAccounts(options.accounts, nowMs, maxRows);
    rows = derived.rows;
    earliestResetMs = derived.earliestResetMs;
  }

  const title = typeof options.title === 'string' && options.title.trim().length > 0
    ? options.title.trim()
    : DEFAULT_USAGE_WIDGET_TITLE;
  const emptyMessage = typeof options.emptyMessage === 'string' && options.emptyMessage.trim().length > 0
    ? options.emptyMessage.trim()
    : 'No active usage limits';
  const explicitMessage = typeof options.message === 'string' ? options.message.trim() : undefined;
  const message = rows.length > 0
    ? (explicitMessage ?? '')
    : (explicitMessage && explicitMessage.length > 0 ? explicitMessage : emptyMessage);
  const asOf = rows.length > 0 && typeof options.asOf === 'string'
    ? options.asOf.trim()
    : '';

  let expiresAtMs: number;
  if (typeof options.expiresAtMs === 'number' && Number.isFinite(options.expiresAtMs)) {
    expiresAtMs = options.expiresAtMs;
  } else if (earliestResetMs !== undefined) {
    expiresAtMs = Math.min(nowMs + ttlMs, earliestResetMs);
  } else {
    expiresAtMs = nowMs + ttlMs;
  }

  return {
    title,
    message,
    asOf,
    rows,
    expiresAtMs,
  };
}

export function isUsageWidgetExpired(
  snapshot: UsageWidgetSnapshot | null | undefined,
  nowMs: number,
): boolean {
  if (!snapshot || !Number.isFinite(snapshot.expiresAtMs) || snapshot.expiresAtMs <= 0) {
    return true;
  }
  if (!Number.isFinite(nowMs)) {
    return true;
  }
  return nowMs >= snapshot.expiresAtMs;
}
