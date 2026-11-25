import * as NodeAssert from "node:assert/strict";
import * as NodeFS from "node:fs";
import * as NodeModule from "node:module";
import * as NodeProcess from "node:process";
import * as NodeTest from "node:test";
import {
  ServerProviderUsageLimits,
  UsageSummary,
  UsageSummaryInput,
  WS_METHODS,
} from "@t3tools/contracts";
import * as Schema from "effect/Schema";

const client = new URL("../entry/src/main/ets/client/", import.meta.url);
const loader = NodeModule.registerHooks({
  resolve(specifier, context, nextResolve) {
    if (specifier.startsWith("./") && context.parentURL?.startsWith(client.href)) {
      return nextResolve(`${specifier}.ets`, context);
    }
    return nextResolve(specifier, context);
  },
  load(url, context, nextLoad) {
    if (!url.startsWith(client.href) || !url.endsWith(".ets")) return nextLoad(url, context);
    return {
      format: "module",
      shortCircuit: true,
      source: NodeModule.stripTypeScriptTypes(NodeFS.readFileSync(new URL(url), "utf8")),
    };
  },
});
NodeTest.after(() => loader.deregister());

const protocol = () => import(new URL("WorkspaceUsageProtocol.ets", client).href);
const decodeSummaryInput = Schema.decodeUnknownSync(Schema.toCodecJson(UsageSummaryInput));
const decodeSummary = Schema.decodeUnknownSync(Schema.toCodecJson(UsageSummary));
const decodeUsageLimits = Schema.decodeUnknownSync(Schema.toCodecJson(ServerProviderUsageLimits));
const now = new Date("2026-03-08T20:02:45.891Z");

NodeTest.test(
  "requests the rolling 24 hours and inclusive local calendar periods",
  async (context) => {
    const previousZone = NodeProcess.env.TZ;
    context.after(() => {
      if (previousZone === undefined) delete NodeProcess.env.TZ;
      else NodeProcess.env.TZ = previousZone;
    });
    NodeProcess.env.TZ = "America/New_York";
    const { workspaceUsageSummaryRequest, workspaceUsageLimitsRequest } = await protocol();
    const hourly = workspaceUsageSummaryRequest(1, now);
    NodeAssert.equal(hourly.tag, WS_METHODS.serverGetUsageSummary);
    NodeAssert.deepEqual(decodeSummaryInput(hourly.payload), {
      sinceDay: "2026-03-07",
      untilDay: "2026-03-08",
      timeZone: "America/New_York",
      resolution: "hour",
      sinceTime: "2026-03-07T20:02:00.000Z",
      untilTime: "2026-03-08T20:02:00.000Z",
    });
    const weekly = workspaceUsageSummaryRequest(7, now);
    NodeAssert.deepEqual(decodeSummaryInput(weekly.payload), {
      sinceDay: "2026-03-02",
      untilDay: "2026-03-08",
      timeZone: "America/New_York",
      resolution: "day",
    });
    NodeAssert.equal(workspaceUsageLimitsRequest().tag, WS_METHODS.serverGetConfig);
  },
);

NodeTest.test(
  "counts cache and reasoning correctly and distinguishes complete and unpriced usage",
  async () => {
    const { readWorkspaceUsageSummary } = await protocol();
    const bucket = {
      day: "2026-03-08",
      hourStart: "2026-03-08T19:00:00.000Z",
      provider: "codex",
      model: "gpt-5",
      totals: {
        uncachedInputTokens: 17,
        cachedInputTokens: 8,
        cacheCreationTokens: 3,
        outputTokens: 12,
        reasoningTokens: 7,
      },
      costUsd: 2,
      cacheSavingsUsd: 0.5,
      categoryCostUsd: { input: 0.3, cacheRead: 0.1, cacheWrite: 0.1, output: 0.5 },
      fastCostUsd: 0.5,
      ultrafastCostUsd: 0.25,
      speedPremiumUsd: 0.15,
      records: 2,
      unpricedRecords: 0,
      sessions: 2,
    };
    const source = {
      fingerprint: {
        provider: "codex",
        hostId: "fixture",
        resolvedHomePath: "/logs",
        volumeId: "",
      },
      status: "partial",
      scannedFiles: 2,
      skippedFiles: 1,
      malformedRecords: 0,
      distinctSessions: 2,
      message: "One log source could not be read",
    };
    const response = decodeSummary({
      contractVersion: 6,
      sinceDay: "2026-03-07",
      untilDay: "2026-03-08",
      timeZone: "America/New_York",
      readAt: now.toISOString(),
      pricing: { status: "fresh", source: "fixture", fetchedAt: now.toISOString(), knownModels: 1 },
      scanDurationMs: 3,
      buckets: [
        { ...bucket, costSource: "modelPriced" },
        {
          ...bucket,
          model: "unknown",
          costUsd: 0,
          cacheSavingsUsd: 0,
          categoryCostUsd: { input: 0, cacheRead: 0, cacheWrite: 0, output: 0 },
          costSource: "unpriced",
          unpricedRecords: 2,
        },
      ],
      sources: [source],
    });
    const summary = readWorkspaceUsageSummary(response);
    NodeAssert.equal(summary.totalTokens, 80);
    NodeAssert.equal(summary.inputTokens, 56);
    NodeAssert.equal(summary.outputTokens, 24);
    NodeAssert.equal(summary.cachedInputTokens, 16);
    NodeAssert.equal(summary.cacheCreationTokens, 6);
    NodeAssert.equal(summary.reasoningTokens, 14);
    NodeAssert.equal(summary.sessions, 2);
    NodeAssert.equal(summary.costUsd, 2);
    NodeAssert.equal(summary.cacheSavingsUsd, 0.5);
    NodeAssert.equal(summary.costByType.output, 0.5);
    NodeAssert.equal(summary.costByType.other, 1);
    NodeAssert.deepEqual(summary.costBySpeed, {
      standard: 1.25,
      fast: 0.5,
      ultrafast: 0.25,
      premium: 0.15,
    });
    NodeAssert.equal(summary.pricedRecords, 2);
    NodeAssert.equal(summary.unpricedRecords, 2);
    NodeAssert.equal(summary.periods[0].totalTokens, 80);
    NodeAssert.equal(summary.periods[0].providers[0].totalTokens, 80);
    NodeAssert.equal(summary.providers[0].costUsd, 2);
    NodeAssert.equal(summary.models[0].model, "gpt-5");
    NodeAssert.equal(summary.models[1].pricedRecords, 0);
    NodeAssert.equal(summary.sources[0].status, "partial");
    const withChart = readWorkspaceUsageSummary(response, {
      sinceDay: response.sinceDay,
      untilDay: response.untilDay,
      timeZone: response.timeZone,
      resolution: "hour",
      sinceTime: "2026-03-07T20:02:00.000Z",
      untilTime: "2026-03-08T20:02:00.000Z",
    });
    NodeAssert.equal(withChart.periods.length, 25);
    NodeAssert.equal(withChart.periods[0].empty, true);
    NodeAssert.equal(withChart.periods[23].totalTokens, 80);
    NodeAssert.equal(withChart.periods[24].empty, true);
    NodeAssert.throws(() => readWorkspaceUsageSummary({ ...response, contractVersion: 3 }), /用量/);
  },
);

NodeTest.test("keeps real limit windows and masks account identity by default", async () => {
  const { readWorkspaceUsageLimits, maskedUsageAccountEmail } = await protocol();
  const usageLimits = decodeUsageLimits({
    checkedAt: now.toISOString(),
    windows: [
      {
        id: "long",
        label: "Weekly",
        kind: "weekly",
        usedPercent: 22.8,
        resetsAt: "2026-03-12T12:00:01.000Z",
        windowDurationMins: 10080,
      },
    ],
    resetCredits: { availableCount: 2, nextExpiresAt: "2026-03-12T12:00:01.000Z" },
  });
  const response = {
    providers: [
      { instanceId: "claude-main", driver: "claude", enabled: true, usageLimits },
      {
        instanceId: "codex",
        driver: "codex",
        enabled: true,
        auth: { email: "one@example.com", label: "Plus" },
        usageLimits: { checkedAt: now.toISOString(), windows: [], zeroSpendCap: true },
      },
      { instanceId: "disabled", driver: "claude", enabled: false, usageLimits },
    ],
  };
  const accounts = readWorkspaceUsageLimits(response);
  NodeAssert.equal(accounts.length, 2);
  NodeAssert.equal(accounts[0].windows[0].remainingPercent, 77);
  NodeAssert.equal(accounts[0].windows[0].resetsAt, usageLimits.windows[0].resetsAt);
  NodeAssert.equal(accounts[0].resetCredits?.availableCount, 2);
  NodeAssert.equal(accounts[1].zeroSpendCap, true);
  NodeAssert.equal(maskedUsageAccountEmail(accounts[1].email), "••••••@••••••");
  NodeAssert.throws(() => readWorkspaceUsageLimits({}), /限额/);
});
