import * as NodeAssert from "node:assert/strict";
import * as NodeFS from "node:fs";
import * as NodeModule from "node:module";
import * as NodeTest from "node:test";
import { OrchestrationMessageContext } from "@t3tools/contracts";
import * as Schema from "effect/Schema";

import {
  detectComposerTrigger,
  serializeComposerFileLink,
} from "../../../../packages/shared/src/composerTrigger.ts";

const protocol = new URL(
  "../entry/src/main/ets/client/ComposerCommandProtocol.ets",
  import.meta.url,
);
const loader = NodeModule.registerHooks({
  load(url, context, nextLoad) {
    if (url !== protocol.href) return nextLoad(url, context);
    return {
      format: "module",
      shortCircuit: true,
      source: NodeModule.stripTypeScriptTypes(NodeFS.readFileSync(new URL(url), "utf8")),
    };
  },
});
NodeTest.after(() => loader.deregister());

NodeTest.test("detects the same typed triggers at the caret as Android", async () => {
  const { detectComposerCommandTrigger } = await import(protocol.href);
  const fixtures = [
    ["/", 1],
    ["检查\n/MODEL", "检查\n/MODEL".length],
    ["Use /etc/hosts now", "Use /et".length],
    ["Use /foo\\bar now", "Use /fo".length],
    ["Read @src/(#1 later", "Read @src/(#1".length],
    ["mail@t3.codes", "mail@t3.codes".length],
    ["Review【#修正】", "Review【#修正".length],
    ["€9.99", "€9.99".length],
    ["€review(#1", "€review(#1".length],
    ["/model opus", "/model opus".length],
    ["//", 2],
  ];
  for (const [draft, caret] of fixtures) {
    NodeAssert.deepEqual(
      detectComposerCommandTrigger(draft, caret),
      detectComposerTrigger(draft, caret) ?? undefined,
      draft,
    );
  }
  NodeAssert.equal(detectComposerCommandTrigger("fix @file", 4, 9), undefined);
});

NodeTest.test(
  "replaces just the range through the caret and restores the insertion cursor",
  async () => {
    const {
      detectComposerCommandTrigger,
      replaceComposerCommandTrigger,
      serializeComposerCommandModel,
      serializeComposerCommandPath,
    } = await import(protocol.href);
    const draft = "🛠 Fix @filrest\nnext";
    const start = "🛠 Fix ".length;
    const trigger = detectComposerCommandTrigger(draft, start + "@fil".length);
    const path = "src (old)/__init__[2]#?.py";
    const link = serializeComposerCommandPath(path);
    NodeAssert.equal(link, serializeComposerFileLink(path));
    NodeAssert.equal(
      serializeComposerCommandPath("src\\word name.txt"),
      serializeComposerFileLink("src\\word name.txt"),
    );
    NodeAssert.deepEqual(replaceComposerCommandTrigger(draft, trigger, link + " "), {
      text: "🛠 Fix " + link + " rest\nnext",
      cursor: start + link.length + 1,
    });
    NodeAssert.deepEqual(
      replaceComposerCommandTrigger(
        "Next /mod question",
        {
          kind: "slash-command",
          query: "mod",
          rangeStart: 5,
          rangeEnd: 9,
        },
        "",
      ),
      { text: "Next  question", cursor: 5 },
    );
    NodeAssert.equal(
      serializeComposerCommandModel("open-code", "anthropic/opus"),
      "model:open-code/anthropic/opus",
    );
  },
);

NodeTest.test(
  "writes valid scoped mention records and keeps only references still in the draft",
  async () => {
    const {
      composerCommandContextReference,
      composerEnvironmentMentionRecord,
      composerThreadMentionRecord,
      referencedComposerCommandContext,
    } = await import(protocol.href);
    const decode = Schema.decodeUnknownSync(Schema.toCodecJson(OrchestrationMessageContext));
    const environment = composerEnvironmentMentionRecord("other-host", "[Relay] Work\\\nstation");
    const thread = composerThreadMentionRecord("other-host", "thread-123", "Read the logs");
    NodeAssert.deepEqual(decode({ version: 1, records: [environment, thread] }).records, [
      {
        version: 1,
        kind: "environment",
        contextId: "environment_other-host",
        label: "Relay Work station",
        environmentId: "other-host",
      },
      {
        version: 1,
        kind: "thread",
        contextId: "thread_thread-123",
        label: "Read the logs",
        title: "Read the logs",
        environmentId: "other-host",
        threadId: "thread-123",
      },
    ]);
    const reference = composerCommandContextReference(thread);
    NodeAssert.equal(reference, "[Read the logs](t3-context://v1/thread/thread_thread-123)");
    NodeAssert.deepEqual(
      referencedComposerCommandContext(
        `Read ${reference} on t3-context://v1/environment/environment_other-host`,
        [environment, thread],
      ),
      [thread],
    );
    NodeAssert.deepEqual(referencedComposerCommandContext("All references removed", [thread]), []);
  },
);

NodeTest.test(
  "includes the PR snapshot used by Android and keeps it while referenced",
  async () => {
    const {
      composerCommandContextReference,
      composerPullRequestMentionRecord,
      referencedComposerCommandContext,
    } = await import(protocol.href);
    const row = {
      number: 17,
      title: "Prevent app from losing focus",
      url: "https://git.example.test/tools/client/-/merge_requests/17",
      headBranch: "focus",
      baseBranch: "main",
      state: "open",
      isDraft: true,
    };
    const record = composerPullRequestMentionRecord(row, "Ref-ABC");
    const decode = Schema.decodeUnknownSync(Schema.toCodecJson(OrchestrationMessageContext));
    NodeAssert.deepEqual(decode({ version: 1, records: [record] }).records, [record]);
    NodeAssert.equal(record.kind, "review-comment");
    NodeAssert.deepEqual(record.pullRequest, row);
    NodeAssert.match(record.text, /^The merge request is #17, titled /);
    const reference = composerCommandContextReference(record);
    NodeAssert.equal(reference, "[#17](t3-context://v1/review-comment/Ref-ABC)");
    NodeAssert.deepEqual(referencedComposerCommandContext("Compare " + reference, [record]), [
      record,
    ]);
  },
);
