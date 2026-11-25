import { REQUEST_ID } from './T3Protocol';

export type WorkspaceUsageView = 'cost' | 'tokens' | 'limits';

export interface NativeUsageMetric {
  costUsd: number;
  totalTokens: number;
  pricedRecords: number;
}

export interface NativeUsagePeriod extends NativeUsageMetric {
  key: string;
  day: string;
  hourStart?: string;
  empty?: boolean;
  providers: NativeUsageProvider[];
}

export interface NativeUsageProvider extends NativeUsageMetric {
  provider: string;
}

export interface NativeUsageModel extends NativeUsageProvider {
  key: string;
  model: string;
}

export interface NativeUsageCostByType {
  input: number;
  cacheRead: number;
  cacheWrite: number;
  output: number;
  other: number;
}

export interface NativeUsageCostBySpeed {
  standard: number;
  fast: number;
  ultrafast: number;
  premium: number;
}

export interface NativeUsageSource {
  provider: string;
  status: string;
  message?: string;
  refreshing: boolean;
}

export interface NativeUsageSummary extends NativeUsageMetric {
  sinceDay: string;
  untilDay: string;
  inputTokens: number;
  uncachedInputTokens: number;
  cachedInputTokens: number;
  cacheCreationTokens: number;
  outputTokens: number;
  reasoningTokens: number;
  sessions: number;
  unpricedRecords: number;
  cacheSavingsUsd: number;
  costByType: NativeUsageCostByType;
  costBySpeed: NativeUsageCostBySpeed;
  periods: NativeUsagePeriod[];
  providers: NativeUsageProvider[];
  models: NativeUsageModel[];
  sources: NativeUsageSource[];
}

export interface NativeUsageLimitWindow {
  id: string;
  kind: string;
  label: string;
  remainingPercent: number;
  resetsAt?: string;
  windowDurationMins?: number;
  modelIds?: string[];
}

export interface NativeUsageResetCredits {
  availableCount: number;
  nextExpiresAt?: string;
}

export interface NativeUsageAccount {
  id: string;
  driver: string;
  name: string;
  email?: string;
  plan?: string;
  checkedAt: string;
  windows: NativeUsageLimitWindow[];
  zeroSpendCap: boolean;
  resetCredits?: NativeUsageResetCredits;
  unavailable?: string;
}

interface UsageSummaryInput {
  sinceDay: string;
  untilDay: string;
  timeZone: string;
  resolution: string;
  sinceTime?: string;
  untilTime?: string;
}

interface UsageSummaryRequest {
  _tag: string;
  id: string;
  tag: string;
  payload: UsageSummaryInput;
  headers: string[][];
}

interface UsageLimitsRequest {
  _tag: string;
  id: string;
  tag: string;
  payload: Record<string, string>;
  headers: string[][];
}

interface UsageTotalsWire {
  uncachedInputTokens: number;
  cachedInputTokens: number;
  cacheCreationTokens: number;
  outputTokens: number;
  reasoningTokens?: number;
}

interface UsageCategoryCostWire {
  input: number;
  cacheRead: number;
  cacheWrite: number;
  output: number;
}

interface UsageBucketWire {
  day: string;
  hourStart?: string;
  provider: string;
  model?: string;
  totals: UsageTotalsWire;
  costUsd: number;
  cacheSavingsUsd?: number;
  categoryCostUsd?: UsageCategoryCostWire;
  fastCostUsd?: number;
  ultrafastCostUsd?: number;
  speedPremiumUsd?: number;
  costSource: string;
  records: number;
  unpricedRecords: number;
}

interface UsageFingerprintWire {
  provider: string;
}

interface UsageSourceWire {
  fingerprint: UsageFingerprintWire;
  status: string;
  message?: string | null;
  distinctSessions: number;
  refreshing?: boolean;
}

interface UsageSummaryWire {
  contractVersion: number;
  sinceDay: string;
  untilDay: string;
  buckets: UsageBucketWire[];
  sources: UsageSourceWire[];
}

interface UsageLimitWindowWire {
  id: string;
  kind: string;
  label: string;
  usedPercent: number;
  resetsAt?: string;
  windowDurationMins?: number;
  modelIds?: string[];
}

interface UsageUnavailableWire {
  reason?: string;
  message?: string;
}

interface UsageLimitsWire {
  checkedAt: string;
  windows: UsageLimitWindowWire[];
  zeroSpendCap?: boolean;
  credentialFingerprint?: string;
  resetCredits?: NativeUsageResetCredits;
  unavailable?: UsageUnavailableWire;
}

interface UsageAuthWire {
  email?: string;
  label?: string;
}

interface UsageProviderWire {
  instanceId: string;
  driver: string;
  displayName?: string;
  enabled: boolean;
  installed?: boolean;
  availability?: string;
  auth?: UsageAuthWire;
  usageLimits?: UsageLimitsWire;
}

interface UsageConfigWire {
  providers: UsageProviderWire[];
}

const HOUR_MS: number = 60 * 60_000;
const DAY_MS: number = 24 * HOUR_MS;
const DAY_PATTERN: RegExp = /^\d{4}-\d{2}-\d{2}$/;

export function workspaceUsageSummaryRequest(days: number, now: Date = new Date()): UsageSummaryRequest {
  const timeZone = new Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC';
  const options: Intl.DateTimeFormatOptions = {
    timeZone: timeZone, year: 'numeric', month: '2-digit', day: '2-digit',
  };
  const format = new Intl.DateTimeFormat('en-CA', options);
  let payload: UsageSummaryInput;
  if (days === 1) {
    const until = new Date(Math.floor(now.getTime() / 60_000) * 60_000);
    const since = new Date(until.getTime() - DAY_MS);
    payload = {
      sinceDay: format.format(since), untilDay: format.format(until), timeZone: timeZone,
      resolution: 'hour', sinceTime: since.toISOString(), untilTime: until.toISOString(),
    };
  } else {
    const untilDay = format.format(now);
    const since = new Date(untilDay);
    since.setUTCDate(since.getUTCDate() - (days - 1));
    payload = {
      sinceDay: since.toISOString().slice(0, 10), untilDay: untilDay, timeZone: timeZone, resolution: 'day',
    };
  }
  return { _tag: 'Request', id: REQUEST_ID, tag: 'server.getUsageSummary', payload: payload, headers: [] };
}

export function workspaceUsageLimitsRequest(): UsageLimitsRequest {
  const payload: Record<string, string> = {};
  return { _tag: 'Request', id: REQUEST_ID, tag: 'server.getConfig', payload: payload, headers: [] };
}

function nonBlank(value?: string | null): boolean {
  return typeof value === 'string' && value.trim().length > 0;
}

function nonNegative(value?: number): boolean {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0;
}

function validInstant(value?: string): boolean {
  return typeof value === 'string' && Number.isFinite(Date.parse(value));
}

function readUsageBucket(bucket: UsageBucketWire): boolean {
  return !!bucket && DAY_PATTERN.test(bucket.day) && nonBlank(bucket.provider) &&
    !!bucket.totals && nonNegative(bucket.totals.uncachedInputTokens) &&
    nonNegative(bucket.totals.cachedInputTokens) && nonNegative(bucket.totals.cacheCreationTokens) &&
    nonNegative(bucket.totals.outputTokens) && nonNegative(bucket.costUsd) &&
    nonNegative(bucket.records) && nonNegative(bucket.unpricedRecords) &&
    bucket.unpricedRecords <= bucket.records &&
    (bucket.costSource === 'unpriced' || bucket.costSource === 'providerReported' || bucket.costSource === 'modelPriced');
}

function incrementMetric(metric: NativeUsageMetric, tokens: number, cost: number, records: number): void {
  metric.totalTokens += tokens;
  metric.costUsd += cost;
  metric.pricedRecords += records;
}

function nonNegativeAmount(value: number = 0): number {
  return nonNegative(value) ? value : 0;
}

function addCostByType(target: NativeUsageCostByType, cost: number, category?: UsageCategoryCostWire): void {
  if (!category || !nonNegative(category.input) || !nonNegative(category.cacheRead) ||
    !nonNegative(category.cacheWrite) || !nonNegative(category.output)) {
    target.other += cost;
    return;
  }
  const categorized = category.input + category.cacheRead + category.cacheWrite + category.output;
  if (categorized > cost + 0.005) {
    target.other += cost;
    return;
  }
  target.input += category.input;
  target.cacheRead += category.cacheRead;
  target.cacheWrite += category.cacheWrite;
  target.output += category.output;
  target.other += Math.max(0, cost - categorized);
}

function chartPeriods(periods: Map<string, NativeUsagePeriod>, request: UsageSummaryInput | undefined,
  sinceDay: string, untilDay: string): NativeUsagePeriod[] {
  if (periods.size > 0 && request) {
    const hourly = request.resolution === 'hour';
    const step = hourly ? HOUR_MS : DAY_MS;
    const since = hourly ? Math.floor(Date.parse(request.sinceTime ?? '') / step) * step : Date.parse(sinceDay);
    const until = hourly ? Date.parse(request.untilTime ?? '') - 1 : Date.parse(untilDay);
    if (until >= since && (until - since) / step <= 90) {
      for (let time = since; time <= until; time += step) {
        const instant = new Date(time).toISOString();
        const day = instant.slice(0, 10);
        const key = hourly ? instant : day;
        if (!periods.has(key)) {
          periods.set(key, {
            key: key, day: day, hourStart: hourly ? instant : undefined, empty: true,
            costUsd: 0, totalTokens: 0, pricedRecords: 0, providers: [],
          });
        }
      }
    }
  }
  return Array.from(periods.values()).sort((left, right) => left.key.localeCompare(right.key));
}

export function readWorkspaceUsageSummary(value?: Object, request?: UsageSummaryInput): NativeUsageSummary {
  const wire = value as UsageSummaryWire | undefined;
  if (!wire || !nonNegative(wire.contractVersion) || wire.contractVersion < 4 ||
    !DAY_PATTERN.test(wire.sinceDay) || !DAY_PATTERN.test(wire.untilDay) ||
    !Array.isArray(wire.buckets) || !Array.isArray(wire.sources)) {
    throw new Error('环境未返回有效的用量统计。');
  }
  const summary: NativeUsageSummary = {
    sinceDay: wire.sinceDay, untilDay: wire.untilDay, costUsd: 0, totalTokens: 0, pricedRecords: 0,
    inputTokens: 0, uncachedInputTokens: 0, cachedInputTokens: 0, cacheCreationTokens: 0, outputTokens: 0,
    reasoningTokens: 0, sessions: 0, unpricedRecords: 0, cacheSavingsUsd: 0,
    costByType: { input: 0, cacheRead: 0, cacheWrite: 0, output: 0, other: 0 },
    costBySpeed: { standard: 0, fast: 0, ultrafast: 0, premium: 0 },
    periods: [], providers: [], models: [], sources: [],
  };
  const periods = new Map<string, NativeUsagePeriod>();
  const providers = new Map<string, NativeUsageProvider>();
  const models = new Map<string, NativeUsageModel>();
  for (const bucket of wire.buckets) {
    if (!readUsageBucket(bucket)) continue;
    const input = bucket.totals.uncachedInputTokens + bucket.totals.cachedInputTokens + bucket.totals.cacheCreationTokens;
    const total = input + bucket.totals.outputTokens;
    const priced = bucket.costSource === 'unpriced' ? 0 : bucket.records - bucket.unpricedRecords;
    const cost = priced > 0 ? bucket.costUsd : 0;
    summary.inputTokens += input;
    summary.uncachedInputTokens += bucket.totals.uncachedInputTokens;
    summary.cachedInputTokens += bucket.totals.cachedInputTokens;
    summary.cacheCreationTokens += bucket.totals.cacheCreationTokens;
    summary.outputTokens += bucket.totals.outputTokens;
    const reasoning = bucket.totals.reasoningTokens;
    if (reasoning !== undefined && nonNegative(reasoning)) summary.reasoningTokens += reasoning;
    const savings = bucket.cacheSavingsUsd;
    if (savings !== undefined && nonNegative(savings)) summary.cacheSavingsUsd += savings;
    summary.unpricedRecords += bucket.records - priced;
    if (cost > 0) {
      addCostByType(summary.costByType, cost, bucket.categoryCostUsd);
      const fast = Math.min(cost, nonNegativeAmount(bucket.fastCostUsd));
      const ultrafast = Math.min(cost - fast, nonNegativeAmount(bucket.ultrafastCostUsd));
      summary.costBySpeed.fast += fast;
      summary.costBySpeed.ultrafast += ultrafast;
      summary.costBySpeed.premium += nonNegativeAmount(bucket.speedPremiumUsd);
      summary.costBySpeed.standard += cost - fast - ultrafast;
    }
    incrementMetric(summary, total, cost, priced);
    const hourStart = bucket.hourStart && validInstant(bucket.hourStart) ?
      new Date(bucket.hourStart).toISOString() : undefined;
    const key = hourStart ?? bucket.day;
    const period: NativeUsagePeriod = periods.get(key) ?? {
      key: key, day: bucket.day, hourStart: hourStart, totalTokens: 0, costUsd: 0, pricedRecords: 0, providers: [],
    };
    incrementMetric(period, total, cost, priced);
    let periodProvider = period.providers.find((item) => item.provider === bucket.provider);
    if (!periodProvider) {
      periodProvider = { provider: bucket.provider, totalTokens: 0, costUsd: 0, pricedRecords: 0 };
      period.providers.push(periodProvider);
    }
    incrementMetric(periodProvider, total, cost, priced);
    periods.set(key, period);
    const provider: NativeUsageProvider = providers.get(bucket.provider) ?? {
      provider: bucket.provider, totalTokens: 0, costUsd: 0, pricedRecords: 0,
    };
    incrementMetric(provider, total, cost, priced);
    providers.set(bucket.provider, provider);
    if (bucket.model) {
      const modelKey = `${bucket.provider}:${bucket.model}`;
      const model: NativeUsageModel = models.get(modelKey) ?? {
        key: modelKey, provider: bucket.provider, model: bucket.model, costUsd: 0, totalTokens: 0, pricedRecords: 0,
      };
      incrementMetric(model, total, cost, priced);
      models.set(modelKey, model);
    }
  }
  summary.periods = chartPeriods(periods, request, summary.sinceDay, summary.untilDay);
  for (const period of summary.periods) {
    period.providers.sort((left, right) => left.provider.localeCompare(right.provider));
  }
  summary.providers = Array.from(providers.values());
  summary.models = Array.from(models.values());
  for (const source of wire.sources) {
    if (!source || !source.fingerprint || !nonBlank(source.fingerprint.provider) ||
      !nonNegative(source.distinctSessions) || !nonBlank(source.status)) continue;
    summary.sessions += source.distinctSessions;
    summary.sources.push({
      provider: source.fingerprint.provider, status: source.status, message: source.message ?? undefined,
      refreshing: source.refreshing === true,
    });
  }
  return summary;
}

function readLimitWindows(windows: UsageLimitWindowWire[]): NativeUsageLimitWindow[] {
  const result: NativeUsageLimitWindow[] = [];
  for (const window of windows) {
    if (!window || !nonBlank(window.id) || !nonBlank(window.label) || !nonBlank(window.kind) ||
      !nonNegative(window.usedPercent) || window.usedPercent > 100) continue;
    result.push({
      id: window.id, kind: window.kind, label: window.label,
      remainingPercent: Math.round(100 - window.usedPercent),
      resetsAt: validInstant(window.resetsAt) ? window.resetsAt : undefined,
      windowDurationMins: nonNegative(window.windowDurationMins) ? window.windowDurationMins : undefined,
      modelIds: Array.isArray(window.modelIds) ? window.modelIds.filter((model) => nonBlank(model)) : undefined,
    });
  }
  return result;
}

export function nativeUsageProviderName(provider: string): string {
  switch (provider) {
    case 'codex': return 'Codex';
    case 'claude': return 'Claude';
    case 'grok': return 'Grok';
    case 'cursor': return 'Cursor';
    case 'opencode': return 'OpenCode';
    case 'antigravity': return 'Antigravity';
    case 'kiro': return 'Kiro';
    case 'pi': return 'Pi';
    case 'muse': return 'Muse Code';
    case 'fx': return 'fx';
    default: return provider;
  }
}

export function readWorkspaceUsageLimits(value?: Object): NativeUsageAccount[] {
  const config = value as UsageConfigWire | undefined;
  if (!config || !Array.isArray(config.providers)) throw new Error('环境未返回有效的账户限额。');
  const accounts = new Map<string, NativeUsageAccount>();
  for (const provider of config.providers) {
    const limits = provider?.usageLimits;
    if (!limits || provider.enabled === false || provider.installed === false || provider.availability === 'unavailable' ||
      !nonBlank(provider.instanceId) || !nonBlank(provider.driver) ||
      !validInstant(limits.checkedAt) || !Array.isArray(limits.windows)) continue;
    const windows = readLimitWindows(limits.windows);
    const key = `${provider.driver}:${limits.credentialFingerprint || provider.instanceId}`;
    const existing = accounts.get(key);
    if (existing && Date.parse(existing.checkedAt) >= Date.parse(limits.checkedAt)) continue;
    const credits = limits.resetCredits;
    const unavailable = limits.unavailable;
    accounts.set(key, {
      id: provider.instanceId, driver: provider.driver, name: provider.displayName || nativeUsageProviderName(provider.driver),
      email: provider.auth?.email, plan: provider.auth?.label, checkedAt: limits.checkedAt, windows: windows,
      zeroSpendCap: limits.zeroSpendCap === true,
      resetCredits: credits && nonNegative(credits.availableCount) ? credits : undefined,
      unavailable: unavailable?.message ?? (unavailable?.reason === 'unsupported' ? '当前账户未提供限额数据。' :
        unavailable?.reason === 'probeFailed' ? '无法读取当前限额。' : undefined),
    });
  }
  return Array.from(accounts.values());
}

export function maskedUsageAccountEmail(email?: string): string {
  if (!email) return '';
  return email.includes('@') ? '••••••@••••••' : '••••••';
}
