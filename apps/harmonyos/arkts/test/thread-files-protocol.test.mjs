import * as NodeAssert from "node:assert/strict";
import * as NodeFS from "node:fs";
import * as NodeModule from "node:module";
import * as NodeTest from "node:test";
import {
  ProjectListEntriesInput,
  ProjectListEntriesResult,
  ProjectReadFileInput,
  ProjectReadFileResult,
  ProjectSearchEntriesInput,
  ProjectSearchEntriesResult,
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
const protocol = import(new URL("ThreadFilesProtocol.ets", client).href);
void protocol.catch(() => {});
NodeTest.after(() => loader.deregister());

const decodeListRequest = Schema.decodeUnknownSync(Schema.toCodecJson(ProjectListEntriesInput));
const decodeReadRequest = Schema.decodeUnknownSync(Schema.toCodecJson(ProjectReadFileInput));
const decodeSearchRequest = Schema.decodeUnknownSync(Schema.toCodecJson(ProjectSearchEntriesInput));
const encodeListResult = Schema.encodeSync(Schema.toCodecJson(ProjectListEntriesResult));
const encodeReadResult = Schema.encodeSync(Schema.toCodecJson(ProjectReadFileResult));
const encodeSearchResult = Schema.encodeSync(Schema.toCodecJson(ProjectSearchEntriesResult));
const cwd = "C:\\repo\\worktree";

NodeTest.test(
  "requests immediate children and preserves the exact file path in the read request",
  async () => {
    const { listThreadFilesRequest, readThreadFileRequest } = await protocol;
    const root = listThreadFilesRequest(cwd, "");
    NodeAssert.deepEqual(root, {
      _tag: "Request",
      id: "1",
      tag: WS_METHODS.projectsListEntries,
      payload: { cwd, directoryPath: "" },
      headers: [],
    });
    NodeAssert.deepEqual(decodeListRequest(root.payload), { cwd, directoryPath: "" });
    NodeAssert.deepEqual(decodeListRequest(listThreadFilesRequest(cwd, "docs/指南").payload), {
      cwd,
      directoryPath: "docs/指南",
    });

    const file = readThreadFileRequest(cwd, "docs/ 报告.txt ");
    NodeAssert.equal(file.tag, WS_METHODS.projectsReadFile);
    NodeAssert.deepEqual(decodeReadRequest(file.payload), {
      cwd,
      relativePath: "docs/ 报告.txt ",
    });
  },
);

NodeTest.test("rejects paths that can address a different file on the host", async () => {
  const { listThreadFilesRequest, readThreadFileRequest } = await protocol;
  for (const path of [
    "../outside",
    "docs/../other",
    "docs\\..\\other",
    "/etc/hosts",
    "\\Windows\\system.ini",
    "C:/host/file",
    "C:host/file",
    "\\\\host\\share\\file",
    "~/outside",
    "~\\outside",
    "docs//name",
    "docs/name\0",
  ]) {
    NodeAssert.throws(() => listThreadFilesRequest(cwd, path), path);
    NodeAssert.throws(() => readThreadFileRequest(cwd, path), path);
  }
  NodeAssert.throws(() => listThreadFilesRequest(cwd, " docs "));
  NodeAssert.throws(() => readThreadFileRequest(cwd, ""));
  NodeAssert.throws(() => readThreadFileRequest(cwd, "a".repeat(513)));
});

NodeTest.test(
  "reads immediate directory entries with stable paths, names and truncation",
  async () => {
    const { readThreadFileDirectory } = await protocol;
    const directory = readThreadFileDirectory(
      encodeListResult({
        entries: [
          { path: "docs/参考 资料", kind: "directory" },
          { path: "docs/ 使用指南.md", kind: "file", ignored: true },
          { path: "docs/posix-name\\", kind: "file" },
        ],
        truncated: true,
      }),
      "docs",
    );
    NodeAssert.deepEqual(directory, {
      entries: [
        { path: "docs/参考 资料", name: "参考 资料", kind: "directory" },
        { path: "docs/ 使用指南.md", name: " 使用指南.md", kind: "file" },
        { path: "docs/posix-name\\", name: "posix-name\\", kind: "file" },
      ],
      truncated: true,
    });
    NodeAssert.deepEqual(
      readThreadFileDirectory(encodeListResult({ entries: [], truncated: false }), ""),
      { entries: [], truncated: false },
    );
  },
);

NodeTest.test("rejects directory entries outside the requested immediate children", async () => {
  const { readThreadFileDirectory } = await protocol;
  for (const path of ["docs", "docs/sub/another", "docs-other/README", "../README", "/README"]) {
    const wire = encodeListResult({ entries: [{ path, kind: "file" }], truncated: false });
    NodeAssert.throws(() => readThreadFileDirectory(wire, "docs"), path);
  }
  NodeAssert.throws(() =>
    readThreadFileDirectory(
      { entries: [{ path: "docs/name", kind: "other" }], truncated: false },
      "docs",
    ),
  );
});

NodeTest.test("sends a bounded workspace search using the Android RPC contract", async () => {
  const { searchThreadFilesRequest } = await protocol;
  const request = searchThreadFilesRequest(` ${cwd} `, "  docs/指南  ");
  NodeAssert.equal(request.tag, WS_METHODS.projectsSearchEntries);
  NodeAssert.deepEqual(decodeSearchRequest(request.payload), {
    cwd,
    query: "docs/指南",
    limit: 200,
  });
  const prefix = "a".repeat(255);
  NodeAssert.deepEqual(
    decodeSearchRequest(searchThreadFilesRequest(cwd, `${prefix} tail`).payload),
    {
      cwd,
      query: prefix,
      limit: 200,
    },
  );
  NodeAssert.throws(() => searchThreadFilesRequest(cwd, "  "));
  NodeAssert.throws(() => searchThreadFilesRequest("", "README"));
});

NodeTest.test("opens file and directory hits by full path across the workspace", async () => {
  const { readThreadFileSearch, listThreadFilesRequest, readThreadFileRequest } = await protocol;
  const hits = readThreadFileSearch(
    encodeSearchResult({
      entries: [
        { path: "docs/参考 资料/指南.md", kind: "file" },
        { path: "src/指南.md", kind: "file" },
        { path: "docs/guides", kind: "directory" },
      ],
      truncated: true,
    }),
  );
  NodeAssert.deepEqual(hits, {
    entries: [
      { path: "docs/参考 资料/指南.md", name: "指南.md", kind: "file" },
      { path: "src/指南.md", name: "指南.md", kind: "file" },
      { path: "docs/guides", name: "guides", kind: "directory" },
    ],
    truncated: true,
  });
  NodeAssert.equal(
    readThreadFileRequest(cwd, hits.entries[0].path).payload.relativePath,
    "docs/参考 资料/指南.md",
  );
  NodeAssert.equal(
    listThreadFilesRequest(cwd, hits.entries[2].path).payload.directoryPath,
    "docs/guides",
  );
  NodeAssert.deepEqual(
    readThreadFileSearch(encodeSearchResult({ entries: [], truncated: false })),
    {
      entries: [],
      truncated: false,
    },
  );
});

NodeTest.test("rejects unsafe, duplicate and malformed workspace search hits", async () => {
  const { readThreadFileSearch } = await protocol;
  for (const path of [
    "../docs",
    "docs\\..\\README",
    "/etc/hosts",
    "C:\\Windows\\win.ini",
    "docs//guide",
  ]) {
    NodeAssert.throws(
      () => readThreadFileSearch({ entries: [{ path, kind: "file" }], truncated: false }),
      { message: "环境返回的文件条目无效。" },
      path,
    );
  }
  const entry = { path: "docs/guide", kind: "file" };
  NodeAssert.throws(() => readThreadFileSearch({ entries: [entry, entry], truncated: false }));
  NodeAssert.throws(() =>
    readThreadFileSearch({ entries: [{ ...entry, kind: "other" }], truncated: false }),
  );
  NodeAssert.throws(() => readThreadFileSearch({ entries: [entry], truncated: "true" }));
});

NodeTest.test("reads only the requested file and retains exact text from the wire", async () => {
  const { readThreadFile } = await protocol;
  const relativePath = "docs/ 报告.txt ";
  const wire = encodeReadResult({
    relativePath,
    contents: "  a\n\n",
    byteLength: 500,
    truncated: true,
  });
  NodeAssert.deepEqual(readThreadFile(wire, relativePath), {
    relativePath,
    contents: "  a\n\n",
    truncated: true,
  });
  NodeAssert.throws(() => readThreadFile(wire, "docs/ 报告.txt"));
  NodeAssert.throws(() => readThreadFile({ ...wire, truncated: "true" }, relativePath));
  NodeAssert.throws(() => readThreadFile({ ...wire, exists: false }, relativePath));
});
