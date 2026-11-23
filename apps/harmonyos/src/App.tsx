import { RegistryContext, useAtomValue } from "@effect/atom-react";
import {
  runAtomCommand,
  squashAtomCommandFailure,
  type AtomCommand,
} from "@t3tools/client-runtime/state/runtime";
import { enabledEnvironmentIds } from "@t3tools/client-runtime/state/connections";
import { derivePendingThreadRequests } from "@t3tools/client-runtime/state/thread-requests";
import {
  CommandId,
  MessageId,
  ThreadId,
  type EnvironmentId,
  type ModelSelection,
  type ProjectId,
  type ProviderApprovalDecision,
  type ProviderApprovalOption,
  type ProviderUserInputAnswers,
  type RuntimeRequestId,
  type RunId,
} from "@t3tools/contracts";
import { buildPairingUrl, parsePairingUrl, readPairingQrPayload } from "@t3tools/shared/remote";
import { parseUrl } from "@t3tools/shared/url";
import * as Option from "effect/Option";
import * as Clock from "effect/Clock";
import * as Effect from "effect/Effect";
import * as Random from "effect/Random";
import { AsyncResult } from "effect/reactivity";
import { useContext, useEffect, useState } from "react";
import {
  ActivityIndicator,
  BackHandler,
  Button,
  // oxlint-disable-next-line eslint/no-restricted-imports -- The mobile native scroll view targets iOS and Android.
  FlatList,
  Keyboard,
  KeyboardAvoidingView,
  Pressable,
  StatusBar,
  StyleSheet,
  Text,
  TextInput,
  TurboModuleRegistry,
  type TurboModule,
  useColorScheme,
  View,
} from "react-native";
import {
  EnvironmentIdentity,
  EnvironmentListCard,
} from "../../mobile/src/features/connection/EnvironmentListContent";
import {
  PairingFormContent,
  PairingScanSurface,
} from "../../mobile/src/features/connection/PairingFormContent";
import { UserMessageBubble } from "../../mobile/src/features/threads/UserMessageBubble";
import { ThreadListTitle } from "../../mobile/src/features/threads/ThreadListTitle";
import {
  DEFAULT_MOBILE_THEME_ID,
  getMobileThemeVariables,
  isDarkThemeColor,
} from "../../mobile/src/lib/mobileTheme";
import { catalog, dispatch, pair, server, shell, threads } from "./runtime";
import { PendingQuestions } from "./PendingQuestions";
import { ModelPicker } from "./ModelPicker";

import { text } from "./labels";
import { WorkspaceActivity, type ActivityDetail } from "./WorkspaceActivity";
import { WorkspaceFiles } from "./WorkspaceFiles";
import {
  SearchField,
  WorkspaceSettings,
  type Appearance,
  type SettingsPage,
} from "./WorkspaceSettings";
import {
  PageBody,
  PageText,
  Toolbar,
  ToolbarAction,
  WorkspaceTabs,
  WorkspaceTheme,
  useWorkspaceTheme,
  type WorkspaceTab,
} from "./WorkspaceUi";

const newId = Effect.gen(function* () {
  const time = yield* Clock.currentTimeMillis;
  const random = yield* Random.next;
  return `harmonyos-${time.toString(36)}-${random.toString(36).slice(2)}`;
});

const defaultApprovalOptions: readonly ProviderApprovalOption[] = [
  { decision: "accept", label: text.allow },
  { decision: "decline", label: text.decline },
];

const lightTheme = getMobileThemeVariables(DEFAULT_MOBILE_THEME_ID, "light");
const darkTheme = getMobileThemeVariables(DEFAULT_MOBILE_THEME_ID, "dark");

function useCommand<Input, Value, Error>(command: AtomCommand<Input, Value, Error>) {
  const registry = useContext(RegistryContext);
  return (input: Input) => runAtomCommand(registry, command, input, { reportFailure: false });
}

function Row({ title, onPress }: { title: string; onPress: () => void }) {
  const theme = useWorkspaceTheme();
  return (
    <Pressable
      accessibilityRole="button"
      onPress={onPress}
      style={[styles.row, { borderBottomColor: theme["--color-border-subtle"] }]}
    >
      <ThreadListTitle style={{ color: theme["--color-foreground"], fontWeight: "500" }}>
        {title}
      </ThreadListTitle>
    </Pressable>
  );
}

function Pairing({
  onConnect,
  back,
}: {
  onConnect: (id: EnvironmentId) => void;
  back?: () => void;
}) {
  const connect = useCommand(pair);
  const [address, setAddress] = useState("");
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState(false);
  const [failure, setFailure] = useState<string | null>(null);
  const [scanning, setScanning] = useState(false);
  const theme = useWorkspaceTheme();
  const light = !isDarkThemeColor(theme["--color-sheet-solid"]);
  const disabled = busy || scanning;

  function changeAddress(value: string) {
    const fields = parsePairingUrl(value);
    setAddress(fields.code ? fields.host : value);
    if (fields.code) setCode(fields.code);
    setFailure(null);
  }

  async function scanCode() {
    if (busy || scanning) return;
    setScanning(true);
    setFailure(null);
    try {
      const scanner = TurboModuleRegistry.getEnforcing<
        TurboModule & {
          scan(): Promise<string | null>;
        }
      >("T3PairingScanner");
      const payload = await scanner.scan();
      if (payload === null) return;
      const link = readPairingQrPayload(payload);
      if (link === null) setFailure(text.scanFailed);
      else changeAddress(link);
    } catch {
      setFailure(text.scanFailed);
    } finally {
      setScanning(false);
    }
  }
  async function submit() {
    const link = buildPairingUrl(address, code);
    if (!link || disabled) return;
    setBusy(true);
    setFailure(null);
    try {
      const result = await connect(link);
      if (result._tag === "Success") onConnect(result.value);
      else {
        const error = squashAtomCommandFailure(result);
        setFailure(error instanceof Error ? error.message : text.pairingFailed);
      }
    } finally {
      setBusy(false);
    }
  }

  return (
    <View style={[styles.conversation, { backgroundColor: theme["--color-sheet-solid"] }]}>
      <Toolbar title={text.addEnvironment} {...(back && !disabled && { back })}>
        <ToolbarAction
          label={text.connect}
          glyph="✓"
          busy={busy}
          disabled={disabled || !address.trim()}
          onPress={() => void submit()}
        />
      </Toolbar>
      <PageBody>
        <PairingFormContent
          scanner={
            <PairingScanSurface
              light={light}
              disabled={disabled}
              scanLabel={text.scan}
              tapLabel={text.tapToScan}
              instructions={text.scanInstructions}
              onPress={() => void scanCode()}
            />
          }
          address={address}
          code={code}
          onAddressChange={changeAddress}
          onCodeChange={(value) => {
            setCode(value);
            setFailure(null);
          }}
          onSubmit={() => void submit()}
          editable={!disabled}
          error={failure}
          colors={{
            foreground: theme["--color-foreground"],
            muted: theme["--color-foreground-muted"],
            placeholder: theme["--color-placeholder"],
            card: theme["--color-grouped-card"],
            border: theme["--color-border-subtle"],
            error: theme["--color-danger-foreground"],
          }}
          labels={{
            manual: text.enterManually,
            address: text.address,
            code: text.code,
            codePlaceholder: text.pairingCode,
            help: text.pairingHelp,
          }}
        />
      </PageBody>
    </View>
  );
}

function Conversation({
  environmentId,
  threadId,
  initialDraft,
  back,
}: {
  environmentId: EnvironmentId;
  threadId: ThreadId;
  initialDraft: string;
  back: () => void;
}) {
  const theme = useWorkspaceTheme();
  const result = useAtomValue(threads.stateAtom(environmentId, threadId));
  const state = AsyncResult.getOrElse(result, () => null);
  const projection = state === null ? null : Option.getOrNull(state.data);
  const canWrite = useAtomValue(dispatch.permissionAtom(environmentId));
  const send = useCommand(dispatch);
  const [draft, setDraft] = useState(initialDraft);
  const [busy, setBusy] = useState(false);
  const [failed, setFailed] = useState(false);

  const [actionFailed, setActionFailed] = useState(false);
  const [actionBusy, setActionBusy] = useState(false);

  const pending = projection && derivePendingThreadRequests(projection);
  const approval = pending && pending.approvals[0];
  const questionRequest = pending && pending.userInputs[0];
  const activeRun = projection?.runs.findLast(
    (run) =>
      run.status === "running" ||
      run.status === "waiting" ||
      run.status === "starting" ||
      run.status === "preparing",
  );

  async function runAction(
    action:
      | {
          type: "runtime-request.respond";
          requestId: RuntimeRequestId;
          decision: ProviderApprovalDecision;
        }
      | {
          type: "runtime-request.respond";
          requestId: RuntimeRequestId;
          answers: ProviderUserInputAnswers;
        }
      | { type: "thread.user-input.dismiss"; requestId: RuntimeRequestId }
      | { type: "run.interrupt"; runId: RunId; holdQueue: true },
  ) {
    if (!canWrite || actionBusy) return;
    setActionBusy(true);
    setActionFailed(false);
    try {
      const result = await send({
        environmentId,
        input: { ...action, threadId, commandId: CommandId.make(Effect.runSync(newId)) },
      });
      setActionFailed(result._tag !== "Success");
    } finally {
      setActionBusy(false);
    }
  }

  async function submit() {
    const message = draft.trim();
    if (!message || !canWrite || busy) return;
    setBusy(true);
    setFailed(false);
    try {
      const id = Effect.runSync(newId);
      const response = await send({
        environmentId,
        input: {
          type: "message.dispatch",
          commandId: CommandId.make(id),
          messageId: MessageId.make(id),
          threadId,
          createdBy: "user",
          creationSource: "mobile",
          text: message,
          attachments: [],
          dispatchMode: { type: "queue_after_active" },
        },
      });
      if (response._tag === "Success") setDraft("");
      else setFailed(true);
    } finally {
      setBusy(false);
    }
  }

  return (
    <View style={[styles.conversation, { backgroundColor: theme["--color-thread-canvas"] }]}>
      <Toolbar title={projection?.thread.title ?? text.threads} back={back} />
      {state && Option.isSome(state.error) && <PageText error>{state.error.value}</PageText>}
      {projection ? (
        <FlatList
          data={projection.messages}
          keyExtractor={(message) => message.id}
          renderItem={({ item }) =>
            item.role === "user" ? (
              <UserMessageBubble color={theme["--color-user-bubble"]} style={styles.userMessage}>
                <Text
                  selectable
                  style={[styles.body, { color: theme["--color-user-bubble-foreground"] }]}
                >
                  {item.text}
                </Text>
              </UserMessageBubble>
            ) : (
              <View style={styles.row}>
                <Text style={[styles.rowTitle, { color: theme["--color-foreground"] }]}>
                  {text[item.role]}
                </Text>
                <Text selectable style={[styles.body, { color: theme["--color-foreground"] }]}>
                  {item.text}
                </Text>
              </View>
            )
          }
          ListEmptyComponent={<PageText muted>{text.noMessages}</PageText>}
          style={styles.list}
          contentContainerStyle={styles.messages}
        />
      ) : !state || (state.status !== "deleted" && Option.isNone(state.error)) ? (
        <ActivityIndicator />
      ) : null}
      {approval && (
        <View style={styles.row}>
          <PageText>{text.approval}</PageText>
          {(approval.detail ?? approval.reason) && (
            <PageText>{approval.detail ?? approval.reason}</PageText>
          )}
          {approval.responseCapability === "not_resumable" ? (
            <PageText muted>{text.approvalExpired}</PageText>
          ) : (
            canWrite && (
              <View style={styles.actions}>
                {(approval.options ?? defaultApprovalOptions).map((option) => (
                  <View key={option.decision} style={styles.approvalOption}>
                    {option.warning && <PageText>{option.warning}</PageText>}
                    <Button
                      title={option.label}
                      disabled={actionBusy}
                      onPress={() =>
                        void runAction({
                          type: "runtime-request.respond",
                          requestId: approval.requestId,
                          decision: option.decision,
                        })
                      }
                    />
                  </View>
                ))}
              </View>
            )
          )}
        </View>
      )}
      {activeRun && canWrite && (
        <Button
          title={text.stop}
          disabled={actionBusy}
          onPress={() =>
            void runAction({
              type: "run.interrupt",
              runId: activeRun.id,
              holdQueue: true,
            })
          }
        />
      )}
      {questionRequest && (
        <PendingQuestions
          key={questionRequest.requestId}
          request={questionRequest}
          labels={text}
          disabled={!canWrite || actionBusy}
          onSubmit={(answers) =>
            void runAction({
              type: "runtime-request.respond",
              requestId: questionRequest.requestId,
              answers,
            })
          }
          onDismiss={() =>
            void runAction({
              type: "thread.user-input.dismiss",
              requestId: questionRequest.requestId,
            })
          }
        />
      )}
      {actionFailed && <PageText error>{text.commandFailed}</PageText>}
      {failed && <PageText error>{text.sendFailed}</PageText>}
      {projection && state?.status === "live" && canWrite && (
        <View
          style={[
            styles.composer,
            {
              borderColor: theme["--color-composer-border"],
              backgroundColor: theme["--color-composer-surface"],
            },
          ]}
        >
          <TextInput
            accessibilityLabel={text.message}
            editable={!busy}
            multiline
            onChangeText={setDraft}
            placeholder={text.message}
            placeholderTextColor={theme["--color-placeholder"]}
            style={[styles.input, { color: theme["--color-foreground"] }]}
            value={draft}
          />
          <ToolbarAction
            label={text.send}
            glyph="↑"
            disabled={busy || !draft.trim()}
            onPress={() => void submit()}
          />
        </View>
      )}
    </View>
  );
}

function Projects({
  environmentId,
  onOpenEnvironments,
  openThread,
}: {
  environmentId: EnvironmentId;
  onOpenEnvironments: () => void;
  openThread: (id: ThreadId, draft?: string) => void;
}) {
  const state = useAtomValue(shell.stateValueAtom(environmentId));
  const config = useAtomValue(server.configValueAtom(environmentId));
  const snapshot = Option.getOrNull(state.snapshot);
  const retry = useCommand(catalog.retryNow);
  const mutate = useCommand(dispatch);
  const canWrite = useAtomValue(dispatch.permissionAtom(environmentId));
  const [projectId, setProjectId] = useState<ProjectId | null>(null);
  const [query, setQuery] = useState("");
  const [showFiles, setShowFiles] = useState(false);
  const [newTask, setNewTask] = useState(false);
  const [taskPrompt, setTaskPrompt] = useState("");
  const [selectingModel, setSelectingModel] = useState(false);
  const [selectedModel, setSelectedModel] = useState<ModelSelection | null>(null);
  const [busy, setBusy] = useState(false);
  const [failed, setFailed] = useState(false);
  const project = snapshot?.projects.find((entry) => entry.id === projectId);
  const activeThreads = snapshot?.threads.filter((entry) => entry.archivedAt === null) ?? [];
  const projectThreads = activeThreads.filter((entry) => entry.projectId === projectId);
  const needle = query.trim().toLocaleLowerCase();
  const results = (project ? projectThreads : activeThreads).filter((entry) =>
    entry.title.toLocaleLowerCase().includes(needle),
  );
  const theme = useWorkspaceTheme();
  const modelSelection =
    selectedModel ??
    project?.defaultModelSelection ??
    config?.settings.defaultModelSelection ??
    projectThreads[0]?.modelSelection;

  async function createThread() {
    if (!project || !modelSelection || !canWrite || busy) return;
    setBusy(true);
    setFailed(false);
    try {
      const id = ThreadId.make(Effect.runSync(newId));
      const result = await mutate({
        environmentId,
        input: {
          type: "thread.create",
          commandId: CommandId.make(id),
          threadId: id,
          projectId: project.id,
          title: text.newThread,
          modelSelection,
          runtimeMode: "approval-required",
          interactionMode: "default",
          creationSource: "mobile",
          createdBy: "user",
          branch: null,
          worktreePath: null,
        },
      });
      if (result._tag === "Success") {
        openThread(id, taskPrompt);
        setNewTask(false);
        setTaskPrompt("");
      } else setFailed(true);
    } finally {
      setBusy(false);
    }
  }

  if (showFiles && project) {
    return (
      <WorkspaceFiles
        environmentId={environmentId}
        cwd={project.workspaceRoot}
        back={() => setShowFiles(false)}
      />
    );
  }

  const modelPicker =
    project && selectingModel ? (
      <ModelPicker
        config={config}
        project={project}
        selection={modelSelection ?? null}
        labels={text}
        onClose={() => setSelectingModel(false)}
        onSelect={(selection) => {
          setSelectedModel(selection);
          setSelectingModel(false);
        }}
      />
    ) : null;

  if (newTask && project) {
    return (
      <>
        <Toolbar title={text.newTask} back={() => setNewTask(false)} />
        <PageBody>
          <PageText muted>{project.title}</PageText>
          <Pressable
            accessibilityRole="button"
            onPress={() => setSelectingModel(true)}
            style={styles.projectActions}
          >
            <PageText>{modelSelection?.model ?? text.selectModel} ⌄</PageText>
          </Pressable>
          <TextInput
            accessibilityLabel={text.message}
            placeholder={text.message}
            placeholderTextColor={theme["--color-placeholder"]}
            editable={!busy}
            multiline
            value={taskPrompt}
            onChangeText={setTaskPrompt}
            style={[
              styles.taskDraft,
              { color: theme["--color-foreground"], borderColor: theme["--color-border-subtle"] },
            ]}
          />
          {failed && <PageText error>{text.commandFailed}</PageText>}
          <Button
            title={text.newThread}
            disabled={!modelSelection || busy || !canWrite}
            onPress={() => void createThread()}
          />
        </PageBody>
        {modelPicker}
      </>
    );
  }

  return (
    <View style={styles.list}>
      <Toolbar
        title={project?.title ?? text.threads}
        {...(project && {
          back: () => {
            setProjectId(null);
            setSelectedModel(null);
            setQuery("");
          },
        })}
      >
        {!project && (
          <ToolbarAction label={text.environments} glyph="◎" onPress={onOpenEnvironments} />
        )}
        {project && (
          <ToolbarAction label={text.files} glyph="▤" onPress={() => setShowFiles(true)} />
        )}
        {project && canWrite && (
          <ToolbarAction
            label={text.newTask}
            glyph="+"
            disabled={busy}
            onPress={() => {
              setFailed(false);
              setNewTask(true);
            }}
          />
        )}
      </Toolbar>
      {snapshot === null && Option.isNone(state.error) && <ActivityIndicator />}
      {Option.isSome(state.error) && (
        <>
          <PageText error>{state.error.value}</PageText>
          <Button title={text.retry} onPress={() => void retry(environmentId)} />
        </>
      )}
      {failed && <PageText error>{text.commandFailed}</PageText>}
      {snapshot && <SearchField value={query} onChangeText={setQuery} />}
      {snapshot &&
        (project || needle ? (
          <>
            <FlatList
              data={results}
              keyExtractor={(entry) => entry.id}
              renderItem={({ item }) => (
                <Row title={item.title} onPress={() => openThread(item.id)} />
              )}
              ListEmptyComponent={
                <PageText muted>{needle ? text.noResults : text.noThreads}</PageText>
              }
              style={styles.list}
              contentContainerStyle={styles.listPadding}
              keyboardShouldPersistTaps="handled"
            />
            {project && canWrite && (
              <View style={styles.projectActions}>
                <Pressable
                  accessibilityRole="button"
                  accessibilityLabel={text.selectModel}
                  disabled={busy}
                  onPress={() => setSelectingModel(true)}
                >
                  <Text style={{ color: theme["--color-foreground"] }}>
                    {modelSelection?.model ?? text.selectModel} ⌄
                  </Text>
                </Pressable>
                {modelPicker}
              </View>
            )}
          </>
        ) : (
          <FlatList
            data={snapshot.projects.filter((entry) => entry.archivedAt == null)}
            keyExtractor={(entry) => entry.id}
            renderItem={({ item }) => (
              <Row
                title={item.title}
                onPress={() => {
                  setProjectId(item.id);
                  setSelectedModel(null);
                }}
              />
            )}
            ListEmptyComponent={<PageText muted>{text.noProjects}</PageText>}
            style={styles.list}
            contentContainerStyle={styles.listPadding}
            keyboardShouldPersistTaps="handled"
          />
        ))}
    </View>
  );
}

type Overlay = "environments" | "environmentDetail" | "pairing";

export default function App() {
  const saved = useAtomValue(catalog.catalogAtom);
  const colorScheme = useColorScheme();
  const [appearance, setAppearance] = useState<Appearance>("systemTheme");
  const light = appearance === "systemTheme" ? colorScheme !== "dark" : appearance === "lightTheme";
  const theme = light ? lightTheme : darkTheme;
  const [selectedId, setEnvironmentId] = useState<EnvironmentId | null>(null);
  const [overlay, setOverlay] = useState<Overlay | null>(null);
  const [inspectingId, setInspectingId] = useState<EnvironmentId | null>(null);
  const [tab, setTab] = useState<WorkspaceTab>("threads");
  const [threadId, setThreadId] = useState<ThreadId | null>(null);
  const [initialDraft, setInitialDraft] = useState("");
  const [detail, setDetail] = useState<ActivityDetail | null>(null);
  const [settingsPage, setSettingsPage] = useState<SettingsPage>("settings");
  const [disconnecting, setDisconnecting] = useState(false);
  const [disconnectFailed, setDisconnectFailed] = useState(false);
  const remove = useCommand(catalog.remove);
  const readyCatalog = saved._tag === "Success" && saved.value.isReady ? saved.value : null;
  const environmentIds = readyCatalog ? Array.from(enabledEnvironmentIds(readyCatalog)) : [];
  const environmentId =
    selectedId !== null && environmentIds.includes(selectedId) ? selectedId : environmentIds[0];
  const inspected = inspectingId ? readyCatalog?.entries.get(inspectingId) : undefined;

  useEffect(() => {
    const subscription = BackHandler.addEventListener("hardwareBackPress", () => {
      if (Keyboard.isVisible()) Keyboard.dismiss();
      else if (overlay === "pairing" && environmentId) setOverlay("environments");
      else if (overlay === "environmentDetail") setOverlay("environments");
      else if (overlay === "environments") setOverlay(null);
      else if (threadId) setThreadId(null);
      else if (detail) setDetail(null);
      else if (tab === "settings" && settingsPage !== "settings") setSettingsPage("settings");
      else if (tab !== "threads") setTab("threads");
      else return false;
      return true;
    });
    return () => subscription.remove();
  }, [overlay, environmentId, threadId, detail, tab, settingsPage]);

  function openProjects(id: EnvironmentId) {
    setEnvironmentId(id);
    setOverlay(null);
    setTab("threads");
    setDetail(null);
    setThreadId(null);
  }

  function openThread(id: ThreadId, draft = "") {
    setInitialDraft(draft);
    setThreadId(id);
  }

  async function disconnect(id: EnvironmentId) {
    if (disconnecting) return;
    setDisconnecting(true);
    setDisconnectFailed(false);
    try {
      const result = await remove(id);
      if (result._tag === "Success") {
        if (id === selectedId) setEnvironmentId(null);
        setInspectingId(null);
        setOverlay("environments");
      } else {
        setDisconnectFailed(true);
      }
    } finally {
      setDisconnecting(false);
    }
  }

  return (
    <WorkspaceTheme value={theme}>
      <KeyboardAvoidingView
        behavior="height"
        style={[styles.page, { backgroundColor: theme["--color-screen"] }]}
      >
        <StatusBar barStyle={light ? "dark-content" : "light-content"} />
        {saved._tag === "Failure" ? (
          <PageBody>
            <PageText error>{text.storeFailed}</PageText>
          </PageBody>
        ) : readyCatalog === null ? (
          <PageBody>
            <ActivityIndicator accessibilityLabel={text.loading} />
          </PageBody>
        ) : overlay === "pairing" || !environmentId ? (
          <Pairing
            onConnect={openProjects}
            {...(environmentId && { back: () => setOverlay("environments") })}
          />
        ) : overlay === "environmentDetail" && inspected && inspectingId ? (
          <>
            <Toolbar title={inspected.target.label} back={() => setOverlay("environments")} />
            <PageBody>
              <PageText muted>{connectionAddress(inspected.profile)}</PageText>
              <Button title={text.switchEnvironment} onPress={() => openProjects(inspectingId)} />
              <Button
                title={text.disconnect}
                disabled={disconnecting}
                onPress={() => void disconnect(inspectingId)}
              />
              {disconnectFailed && <PageText error>{text.commandFailed}</PageText>}
            </PageBody>
          </>
        ) : overlay === "environments" ? (
          <>
            <Toolbar title={text.environments} back={() => setOverlay(null)}>
              <ToolbarAction
                label={text.addEnvironment}
                glyph="+"
                onPress={() => setOverlay("pairing")}
              />
            </Toolbar>
            <PageBody>
              <EnvironmentListCard color={theme["--color-grouped-card"]}>
                {environmentIds.map((id, index) => {
                  const entry = readyCatalog.entries.get(id);
                  if (!entry) return null;
                  return (
                    <View
                      key={id}
                      style={[
                        styles.environmentRow,
                        index > 0 && {
                          borderTopWidth: StyleSheet.hairlineWidth,
                          borderTopColor: theme["--color-border-subtle"],
                        },
                      ]}
                    >
                      <Pressable
                        accessibilityRole="button"
                        accessibilityState={{ selected: id === environmentId }}
                        onPress={() => openProjects(id)}
                        style={styles.environmentIdentity}
                      >
                        <EnvironmentIdentity
                          name={entry.target.label}
                          address={connectionAddress(entry.profile)}
                          foreground={theme["--color-foreground"]}
                          muted={theme["--color-foreground-muted"]}
                        />
                      </Pressable>
                      <ToolbarAction
                        label={entry.target.label}
                        glyph="›"
                        onPress={() => {
                          setDisconnectFailed(false);
                          setInspectingId(id);
                          setOverlay("environmentDetail");
                        }}
                      />
                    </View>
                  );
                })}
              </EnvironmentListCard>
            </PageBody>
          </>
        ) : (
          <>
            {tab === "threads" && (
              <View style={threadId ? styles.offscreen : styles.list}>
                <Projects
                  key={environmentId}
                  environmentId={environmentId}
                  onOpenEnvironments={() => setOverlay("environments")}
                  openThread={openThread}
                />
              </View>
            )}
            {threadId !== null ? (
              <Conversation
                key={threadId}
                environmentId={environmentId}
                threadId={threadId}
                initialDraft={initialDraft}
                back={() => setThreadId(null)}
              />
            ) : tab === "settings" ? (
              <WorkspaceSettings
                page={settingsPage}
                appearance={appearance}
                onAppearance={setAppearance}
                onPage={setSettingsPage}
                environmentId={environmentId}
                environmentCount={environmentIds.length}
                onEnvironments={() => setOverlay("environments")}
                openThread={openThread}
              />
            ) : tab !== "threads" ? (
              <WorkspaceActivity
                key={environmentId}
                tab={tab}
                environmentId={environmentId}
                detail={detail}
                setDetail={setDetail}
              />
            ) : null}
            {threadId === null && detail === null && (
              <WorkspaceTabs
                selected={tab}
                onSelect={(value) => {
                  Keyboard.dismiss();
                  setTab(value);
                  setDetail(null);
                }}
              />
            )}
          </>
        )}
      </KeyboardAvoidingView>
    </WorkspaceTheme>
  );
}

function connectionAddress(
  profile: Option.Option<{ readonly _tag: string; readonly httpBaseUrl?: string }>,
) {
  const value = Option.getOrNull(profile);
  return value?._tag === "BearerConnectionProfile" && value.httpBaseUrl
    ? (parseUrl(value.httpBaseUrl)?.host ?? "")
    : "";
}

const styles = StyleSheet.create({
  page: { flex: 1, paddingTop: 40 },
  conversation: { flex: 1 },
  environmentRow: { flexDirection: "row", alignItems: "center", marginStart: 16, paddingEnd: 4 },
  environmentIdentity: { flex: 1, minWidth: 0, gap: 2, paddingVertical: 14 },
  userMessage: {
    alignSelf: "flex-end",
    maxWidth: "88%",
    paddingHorizontal: 14,
    paddingVertical: 10,
    marginVertical: 6,
  },
  messages: { padding: 16 },
  composer: {
    flexDirection: "row",
    alignItems: "flex-end",
    borderWidth: 1,
    borderRadius: 27,
    marginHorizontal: 12,
    marginBottom: 16,
    paddingEnd: 4,
  },
  input: {
    flex: 1,
    minHeight: 44,
    maxHeight: 140,
    paddingHorizontal: 14,
    paddingVertical: 10,
    textAlignVertical: "center",
  },
  row: { gap: 4, paddingVertical: 14, borderBottomWidth: StyleSheet.hairlineWidth },
  rowTitle: { fontSize: 16, fontWeight: "600" },
  actions: { flexDirection: "row", flexWrap: "wrap", gap: 8 },
  approvalOption: { maxWidth: "100%", gap: 4 },
  body: { fontSize: 16 },
  list: { flex: 1 },
  listPadding: { paddingHorizontal: 16, paddingTop: 4 },
  projectActions: { paddingHorizontal: 16, paddingVertical: 8 },
  taskDraft: {
    minHeight: 120,
    borderRadius: 18,
    borderWidth: 1,
    padding: 14,
    textAlignVertical: "top",
  },
  offscreen: { display: "none" },
});
