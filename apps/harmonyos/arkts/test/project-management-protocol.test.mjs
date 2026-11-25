import * as NodeAssert from "node:assert/strict";
import * as NodeFS from "node:fs";
import * as NodeModule from "node:module";
import * as NodeTest from "node:test";
import {
  AuthOrchestrationOperateScope,
  FilesystemBrowseInput,
  FilesystemBrowseResult,
  ProjectMutation,
  WS_METHODS,
} from "@t3tools/contracts";
import { requiredScopesForProjectMutation } from "@t3tools/contracts/settings";
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

const protocol = () => import(new URL("ProjectManagementProtocol.ets", client).href);
const project = { id: "project", title: "Project", workspaceRoot: "/projects/project" };
const timestamp = "2026-11-24T12:00:00.000Z";
const decodeBrowseInput = Schema.decodeUnknownSync(Schema.toCodecJson(FilesystemBrowseInput));
const decodeBrowseResult = Schema.decodeUnknownSync(Schema.toCodecJson(FilesystemBrowseResult));

NodeTest.test(
  "only browses valid host folder paths and consumes the directory listing contract",
  async () => {
    const { projectBrowseRequest, readProjectFolderListing } = await protocol();
    const request = projectBrowseRequest(" ~/work folders/ ");
    NodeAssert.equal(request.tag, WS_METHODS.filesystemBrowse);
    NodeAssert.deepEqual(decodeBrowseInput(request.payload), { partialPath: "~/work folders/" });
    const listing = {
      parentPath: "C:\\Work",
      entries: [{ name: "Example", fullPath: "C:\\Work\\Example" }],
    };
    NodeAssert.deepEqual(readProjectFolderListing(listing), decodeBrowseResult(listing));
    for (const path of ["  ", "~/bad\0name", "/".repeat(513)]) {
      NodeAssert.throws(() => projectBrowseRequest(path), /路径/);
    }
    NodeAssert.throws(
      () => readProjectFolderListing({ parentPath: "/work", entries: [{ name: "Dir" }] }),
      /目录/,
    );
  },
);

NodeTest.test(
  "lists active and archived projects with pinned projects first and hides scratch",
  async () => {
    const { readManagedProjects, projectsOnShelf } = await protocol();
    const projects = readManagedProjects(
      {
        projects: [
          project,
          { ...project, id: "pinned", pinnedAt: timestamp, archivedAt: null },
          { ...project, id: "archived", archivedAt: timestamp, pinnedAt: null },
          { ...project, id: "deleted", deletedAt: timestamp },
          { ...project, id: "scratch", workspaceRoot: "C:\\T3\\scratch" },
          { ...project, id: "", title: null },
        ],
      },
      { scratchWorkspaceRoot: "c:/T3/Scratch/" },
    );
    NodeAssert.deepEqual(
      projectsOnShelf(projects, false).map((item) => item.id),
      ["pinned", "project"],
    );
    NodeAssert.deepEqual(
      projectsOnShelf(projects, true).map((item) => item.id),
      ["archived"],
    );
    NodeAssert.deepEqual(projects[0], { ...project, pinned: false, archived: false });
    NodeAssert.throws(() => readManagedProjects({}), /项目列表/);
  },
);

NodeTest.test("gates project operations by permission, capability, and current state", async () => {
  const { availableProjectActions, readManagedProject, supportsProjectOrganization } =
    await protocol();
  const active = readManagedProject(project);
  const archived = readManagedProject({ ...project, archivedAt: timestamp, pinnedAt: timestamp });
  NodeAssert.equal(supportsProjectOrganization({}), false);
  NodeAssert.equal(
    supportsProjectOrganization({ environment: { capabilities: { projectOrganization: true } } }),
    true,
  );
  NodeAssert.deepEqual(availableProjectActions(active, false, true), []);
  NodeAssert.deepEqual(availableProjectActions(active, true, false), ["rename"]);
  NodeAssert.deepEqual(availableProjectActions(active, true, true), ["rename", "pin", "archive"]);
  NodeAssert.deepEqual(availableProjectActions(archived, true, true), [
    "rename",
    "unpin",
    "restore",
  ]);
});

NodeTest.test("encodes permission-scoped project mutations without creating a folder", async () => {
  const { projectManagementRequest } = await protocol();
  const decode = Schema.decodeUnknownSync(Schema.toCodecJson(ProjectMutation));
  for (const [action, value, fields] of [
    ["rename", "  Test name  ", { title: "Test name" }],
    ["pin", undefined, { pinned: true }],
    ["unpin", undefined, { pinned: false }],
    ["archive", undefined, { archived: true }],
    ["restore", undefined, { archived: false }],
    [
      "add",
      " /projects/Existing Folder/ ",
      {
        title: "Existing Folder",
        workspaceRoot: "/projects/Existing Folder/",
        createWorkspaceRootIfMissing: false,
      },
    ],
  ]) {
    const request = projectManagementRequest("command", "project", { action, value });
    NodeAssert.equal(request.tag, WS_METHODS.projectsMutate);
    const mutation = decode(request.payload);
    NodeAssert.deepEqual(mutation, {
      type: action === "add" ? "project.create" : "project.update",
      commandId: "command",
      projectId: "project",
      ...fields,
    });
    NodeAssert.deepEqual(requiredScopesForProjectMutation(mutation), [
      AuthOrchestrationOperateScope,
    ]);
  }
  const added = (value) =>
    decode(projectManagementRequest("command", "project", { action: "add", value }).payload);
  NodeAssert.equal(added("C:\\Projects\\Example\\").title, "Example");
  NodeAssert.equal(added("\\\\Server\\Share\\Example").title, "Example");
  NodeAssert.equal(added("~/Example").workspaceRoot, "~/Example");
  NodeAssert.throws(() => added("relative/example"), /绝对路径/);
  NodeAssert.throws(() => added("file:///projects/example"), /绝对路径/);
  NodeAssert.throws(
    () => projectManagementRequest("command", "project", { action: "rename", value: " " }),
    /项目名称/,
  );
});

NodeTest.test(
  "rejects directory paths that the server would resolve relative to its own working directory",
  async () => {
    const { projectManagementRequest } = await protocol();
    const add = (value, os) =>
      projectManagementRequest(
        "command",
        "project",
        { action: "add", value },
        {
          environment: { platform: { os } },
        },
      ).payload;
    NodeAssert.throws(() => add("D:\\Projects\\Example", "linux"), /绝对路径/);
    NodeAssert.throws(() => add("/projects/example", "windows"), /绝对路径/);
    NodeAssert.throws(() => add("D:relative", "windows"), /绝对路径/);
    NodeAssert.equal(add("/projects/Example", "darwin").title, "Example");
    NodeAssert.equal(add("~\\Projects\\Example", "windows").title, "Example");
  },
);
