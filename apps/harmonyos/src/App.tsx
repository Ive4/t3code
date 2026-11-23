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
import { readPairingQrPayload } from "@t3tools/shared/remote";
import { parseUrl } from "@t3tools/shared/url";
import * as Option from "effect/Option";
import * as Clock from "effect/Clock";
import * as Effect from "effect/Effect";
import * as Random from "effect/Random";
import { AsyncResult } from "effect/reactivity";
import { useContext, useState } from "react";
import {
  ActivityIndicator,
  Button,
  // oxlint-disable-next-line eslint/no-restricted-imports -- The mobile native scroll view targets iOS and Android.
  FlatList,
  I18nManager,
  KeyboardAvoidingView,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  TurboModuleRegistry,
  type TurboModule,
  View,
} from "react-native";
import { catalog, dispatch, pair, server, shell, threads } from "./runtime";
import { PendingQuestions } from "./PendingQuestions";
import { ModelPicker } from "./ModelPicker";

const text = I18nManager.getConstants().localeIdentifier?.startsWith("zh")
  ? {
      connect: "连接",
      pairingLink: "配对链接",
      pairingFailed: "无法连接此环境。",
      scan: "扫描配对二维码",
      scanFailed: "无法扫描配对二维码。",
      environments: "环境",
      addEnvironment: "添加环境",
      projects: "项目",
      noProjects: "此环境没有项目。",
      threads: "会话",
      noThreads: "此项目没有会话。",
      newThread: "新建会话",
      selectModel: "选择模型",
      noDefaultModel: "请为新会话选择模型。",
      noModels: "此项目没有可用模型。",
      noMessages: "此会话没有消息。",
      back: "返回",
      disconnect: "断开连接",
      retry: "重试",
      message: "输入消息",
      send: "发送",
      sendFailed: "消息未发送。",
      commandFailed: "操作失败。",
      approval: "代理请求审批",
      allow: "允许一次",
      decline: "拒绝",
      stop: "停止任务",
      storeFailed: "无法读取已保存的连接。",
      approvalExpired: "此审批已无法响应。",
      answer: "输入答案",
      submitAnswers: "提交答案",
      dismiss: "忽略",
      requestExpired: "此问题已无法回答。",
      user: "你",
      assistant: "代理",
      system: "系统",
    }
  : {
      connect: "Connect",
      pairingLink: "Pairing link",
      pairingFailed: "Could not connect to this environment.",
      scan: "Scan pairing QR code",
      scanFailed: "Could not scan a pairing QR code.",
      environments: "Environments",
      addEnvironment: "Add environment",
      projects: "Projects",
      noProjects: "This environment has no projects.",
      threads: "Threads",
      noThreads: "This project has no threads.",
      newThread: "New thread",
      selectModel: "Choose model",
      noDefaultModel: "Choose a model for the new thread.",
      noModels: "No models are available for this project.",
      noMessages: "This thread has no messages.",
      back: "Back",
      disconnect: "Disconnect",
      retry: "Retry",
      message: "Message",
      send: "Send",
      sendFailed: "The message was not sent.",
      commandFailed: "The action failed.",
      approval: "Agent approval request",
      allow: "Allow once",
      decline: "Decline",
      stop: "Stop run",
      storeFailed: "Could not read saved connections.",
      approvalExpired: "This approval can no longer be answered.",
      answer: "Enter an answer",
      submitAnswers: "Submit answers",
      dismiss: "Dismiss",
      requestExpired: "This question can no longer be answered.",
      user: "You",
      assistant: "Agent",
      system: "System",
    };

const newId = Effect.gen(function* () {
  const time = yield* Clock.currentTimeMillis;
  const random = yield* Random.next;
  return `harmonyos-${time.toString(36)}-${random.toString(36).slice(2)}`;
});

const defaultApprovalOptions: readonly ProviderApprovalOption[] = [
  { decision: "accept", label: text.allow },
  { decision: "decline", label: text.decline },
];

function useCommand<Input, Value, Error>(command: AtomCommand<Input, Value, Error>) {
  const registry = useContext(RegistryContext);
  return (input: Input) => runAtomCommand(registry, command, input, { reportFailure: false });
}

function Row({
  title,
  subtitle,
  onPress,
}: {
  title: string;
  subtitle?: string;
  onPress: () => void;
}) {
  return (
    <Pressable accessibilityRole="button" onPress={onPress} style={styles.row}>
      <Text style={styles.rowTitle}>{title}</Text>
      {subtitle && <Text style={styles.body}>{subtitle}</Text>}
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
  const [url, setUrl] = useState("");
  const [busy, setBusy] = useState(false);
  const [failure, setFailure] = useState<string | null>(null);
  const [scanning, setScanning] = useState(false);
  const [scanFailed, setScanFailed] = useState(false);

  async function scanCode() {
    if (busy || scanning) return;
    setScanning(true);
    setScanFailed(false);
    try {
      const scanner = TurboModuleRegistry.getEnforcing<
        TurboModule & {
          scan(): Promise<string | null>;
        }
      >("T3PairingScanner");
      const payload = await scanner.scan();
      if (payload === null) return;
      const link = readPairingQrPayload(payload);
      if (link === null) setScanFailed(true);
      else {
        setUrl(link);
        setFailure(null);
      }
    } catch {
      setScanFailed(true);
    } finally {
      setScanning(false);
    }
  }
  async function submit() {
    const link = url.trim();
    if (!link || busy || scanning) return;
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
    <View style={styles.content}>
      {back && <Button title={text.back} disabled={busy || scanning} onPress={back} />}
      <Text style={styles.title}>T3 Code</Text>
      <TextInput
        accessibilityLabel={text.pairingLink}
        autoCapitalize="none"
        autoCorrect={false}
        editable={!busy && !scanning}
        keyboardType="url"
        onChangeText={setUrl}
        onSubmitEditing={() => void submit()}
        placeholder={text.pairingLink}
        style={styles.input}
        value={url}
      />
      <Button
        title={text.connect}
        disabled={busy || scanning || !url.trim()}
        onPress={() => void submit()}
      />
      <Button title={text.scan} disabled={busy || scanning} onPress={() => void scanCode()} />
      {busy && <ActivityIndicator />}
      {scanFailed && (
        <Text accessibilityRole="alert" style={styles.error}>
          {text.scanFailed}
        </Text>
      )}
      {failure !== null && (
        <Text accessibilityRole="alert" style={styles.error}>
          {failure}
        </Text>
      )}
    </View>
  );
}

function Conversation({
  environmentId,
  threadId,
  back,
}: {
  environmentId: EnvironmentId;
  threadId: ThreadId;
  back: () => void;
}) {
  const result = useAtomValue(threads.stateAtom(environmentId, threadId));
  const state = AsyncResult.getOrElse(result, () => null);
  const projection = state === null ? null : Option.getOrNull(state.data);
  const canWrite = useAtomValue(dispatch.permissionAtom(environmentId));
  const send = useCommand(dispatch);
  const [draft, setDraft] = useState("");
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
    <View style={styles.content}>
      <Button title={text.back} onPress={back} />
      <Text style={styles.title}>{projection?.thread.title ?? text.threads}</Text>
      {state && Option.isSome(state.error) && (
        <Text accessibilityRole="alert" style={styles.error}>
          {state.error.value}
        </Text>
      )}
      {projection ? (
        <FlatList
          data={projection.messages}
          keyExtractor={(message) => message.id}
          renderItem={({ item }) => (
            <View style={styles.row}>
              <Text style={styles.rowTitle}>{text[item.role]}</Text>
              <Text selectable style={styles.body}>
                {item.text}
              </Text>
            </View>
          )}
          ListEmptyComponent={<Text style={styles.body}>{text.noMessages}</Text>}
          style={styles.list}
        />
      ) : !state || (state.status !== "deleted" && Option.isNone(state.error)) ? (
        <ActivityIndicator />
      ) : null}
      {approval && (
        <View style={styles.row}>
          <Text style={styles.rowTitle}>{text.approval}</Text>
          {(approval.detail ?? approval.reason) && (
            <Text selectable numberOfLines={5} style={styles.body}>
              {approval.detail ?? approval.reason}
            </Text>
          )}
          {approval.responseCapability === "not_resumable" ? (
            <Text style={styles.body}>{text.approvalExpired}</Text>
          ) : (
            canWrite && (
              <View style={styles.actions}>
                {(approval.options ?? defaultApprovalOptions).map((option) => (
                  <View key={option.decision} style={styles.approvalOption}>
                    {option.warning && <Text style={styles.body}>{option.warning}</Text>}
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
      {actionFailed && (
        <Text accessibilityRole="alert" style={styles.error}>
          {text.commandFailed}
        </Text>
      )}
      {failed && (
        <Text accessibilityRole="alert" style={styles.error}>
          {text.sendFailed}
        </Text>
      )}
      {projection && state?.status === "live" && canWrite && (
        <>
          <TextInput
            accessibilityLabel={text.message}
            editable={!busy}
            multiline
            onChangeText={setDraft}
            placeholder={text.message}
            style={styles.input}
            value={draft}
          />
          <Button
            title={text.send}
            disabled={busy || !draft.trim()}
            onPress={() => void submit()}
          />
        </>
      )}
    </View>
  );
}

function Projects({
  environmentId,
  onDisconnect,
  onOpenEnvironments,
}: {
  environmentId: EnvironmentId;
  onDisconnect: () => void;
  onOpenEnvironments: () => void;
}) {
  const state = useAtomValue(shell.stateValueAtom(environmentId));
  const config = useAtomValue(server.configValueAtom(environmentId));
  const snapshot = Option.getOrNull(state.snapshot);
  const remove = useCommand(catalog.remove);
  const retry = useCommand(catalog.retryNow);
  const mutate = useCommand(dispatch);
  const canWrite = useAtomValue(dispatch.permissionAtom(environmentId));
  const [projectId, setProjectId] = useState<ProjectId | null>(null);
  const [threadId, setThreadId] = useState<ThreadId | null>(null);
  const [selectingModel, setSelectingModel] = useState(false);
  const [selectedModel, setSelectedModel] = useState<ModelSelection | null>(null);
  const [busy, setBusy] = useState(false);
  const [disconnecting, setDisconnecting] = useState(false);
  const [failed, setFailed] = useState(false);
  const project = snapshot?.projects.find((entry) => entry.id === projectId);
  const projectThreads = snapshot?.threads.filter((entry) => entry.projectId === projectId) ?? [];
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
      if (result._tag === "Success") setThreadId(id);
      else setFailed(true);
    } finally {
      setBusy(false);
    }
  }

  async function disconnect() {
    if (disconnecting) return;
    setDisconnecting(true);
    setFailed(false);
    try {
      const result = await remove(environmentId);
      if (result._tag === "Success") onDisconnect();
      else setFailed(true);
    } finally {
      setDisconnecting(false);
    }
  }

  if (threadId !== null) {
    return (
      <Conversation
        key={threadId}
        environmentId={environmentId}
        threadId={threadId}
        back={() => setThreadId(null)}
      />
    );
  }

  return (
    <View style={styles.content}>
      {project ? (
        <Button
          title={text.back}
          onPress={() => {
            setProjectId(null);
            setSelectedModel(null);
          }}
        />
      ) : (
        <Button title={text.environments} disabled={disconnecting} onPress={onOpenEnvironments} />
      )}
      <Text style={styles.title}>{project?.title ?? text.projects}</Text>
      {snapshot === null && Option.isNone(state.error) && <ActivityIndicator />}
      {Option.isSome(state.error) && (
        <>
          <Text accessibilityRole="alert" style={styles.error}>
            {state.error.value}
          </Text>
          <Button title={text.retry} onPress={() => void retry(environmentId)} />
        </>
      )}
      {failed && (
        <Text accessibilityRole="alert" style={styles.error}>
          {text.commandFailed}
        </Text>
      )}
      {project ? (
        <>
          <FlatList
            data={projectThreads}
            keyExtractor={(entry) => entry.id}
            renderItem={({ item }) => (
              <Row title={item.title} onPress={() => setThreadId(item.id)} />
            )}
            ListEmptyComponent={<Text style={styles.body}>{text.noThreads}</Text>}
            style={styles.list}
          />
          {canWrite && (
            <>
              <Button
                title={text.selectModel}
                disabled={busy}
                onPress={() => setSelectingModel(true)}
              />
              {modelSelection ? (
                <>
                  <Text style={styles.body}>{modelSelection.model}</Text>
                  <Button
                    title={text.newThread}
                    disabled={busy}
                    onPress={() => void createThread()}
                  />
                </>
              ) : (
                <Text style={styles.body}>{text.noDefaultModel}</Text>
              )}
              {selectingModel && (
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
              )}
            </>
          )}
        </>
      ) : snapshot !== null ? (
        <FlatList
          data={snapshot.projects.filter((entry) => entry.archivedAt == null)}
          keyExtractor={(entry) => entry.id}
          renderItem={({ item }) => (
            <Row title={item.title} onPress={() => setProjectId(item.id)} />
          )}
          ListEmptyComponent={<Text style={styles.body}>{text.noProjects}</Text>}
          style={styles.list}
        />
      ) : null}
      {!project && (
        <Button
          title={text.disconnect}
          disabled={disconnecting}
          onPress={() => void disconnect()}
        />
      )}
    </View>
  );
}

export default function App() {
  const saved = useAtomValue(catalog.catalogAtom);
  const [selectedId, setEnvironmentId] = useState<EnvironmentId | null>(null);
  const [screen, setScreen] = useState<"projects" | "environments" | "pairing">("projects");
  const readyCatalog = saved._tag === "Success" && saved.value.isReady ? saved.value : null;
  const environmentIds = readyCatalog ? Array.from(enabledEnvironmentIds(readyCatalog)) : [];
  const environmentId =
    selectedId !== null && environmentIds.includes(selectedId) ? selectedId : environmentIds[0];

  function openProjects(id: EnvironmentId) {
    setEnvironmentId(id);
    setScreen("projects");
  }

  return (
    <KeyboardAvoidingView behavior="height" style={styles.screen}>
      {saved._tag === "Failure" ? (
        <View style={styles.content}>
          <Text accessibilityRole="alert" style={styles.error}>
            {text.storeFailed}
          </Text>
        </View>
      ) : readyCatalog === null ? (
        <View style={styles.content}>
          <ActivityIndicator />
        </View>
      ) : screen === "pairing" || !environmentId ? (
        <Pairing
          onConnect={openProjects}
          {...(environmentId && { back: () => setScreen("environments") })}
        />
      ) : screen === "environments" ? (
        <View style={styles.content}>
          <Button title={text.back} onPress={() => setScreen("projects")} />
          <Text style={styles.title}>{text.environments}</Text>
          <FlatList
            data={environmentIds}
            keyExtractor={(id) => id}
            renderItem={({ item }) => {
              const entry = readyCatalog.entries.get(item);
              if (!entry) return null;
              const profile = Option.getOrNull(entry.profile);
              const subtitle =
                profile?._tag === "BearerConnectionProfile"
                  ? parseUrl(profile.httpBaseUrl)?.host
                  : undefined;
              return (
                <Row
                  title={entry.target.label}
                  {...(subtitle && { subtitle })}
                  onPress={() => openProjects(item)}
                />
              );
            }}
            style={styles.list}
          />
          <Button title={text.addEnvironment} onPress={() => setScreen("pairing")} />
        </View>
      ) : (
        <Projects
          key={environmentId}
          environmentId={environmentId}
          onDisconnect={() => {
            setEnvironmentId(null);
            setScreen("environments");
          }}
          onOpenEnvironments={() => setScreen("environments")}
        />
      )}
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: "#fff" },
  content: { flex: 1, gap: 12, padding: 20, paddingTop: 44 },
  title: { color: "#171717", fontSize: 26, fontWeight: "600" },
  input: { borderColor: "#8b8b8b", borderWidth: 1, borderRadius: 8, padding: 12, color: "#171717" },
  row: { gap: 4, paddingVertical: 14, borderBottomColor: "#dedede", borderBottomWidth: 1 },
  rowTitle: { color: "#171717", fontSize: 16, fontWeight: "600" },
  actions: { flexDirection: "row", flexWrap: "wrap", gap: 8 },
  approvalOption: { maxWidth: "100%", gap: 4 },
  body: { color: "#282828", fontSize: 16 },
  list: { flex: 1 },
  error: { color: "#a32121" },
});
