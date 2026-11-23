import { useAtomValue } from "@effect/atom-react";
import { sessionDeniesScope } from "@t3tools/client-runtime/state/session";
import {
  AuthDiagnosticsReadScope,
  USAGE_CONTRACT_VERSION,
  type EnvironmentId,
  type IssueListEntry,
  type PullRequestListEntry,
} from "@t3tools/contracts";
import { formatTokens, formatUsd, makeWindow } from "@t3tools/shared/usageFormat";
import { mergeUsage } from "@t3tools/shared/usageMerge";
import { AsyncResult } from "effect/reactivity";
import { useState } from "react";
import { ActivityIndicator, Linking, StyleSheet, Text, View } from "react-native";

import { EnvironmentListCard } from "../../mobile/src/features/connection/EnvironmentListContent";
import { text } from "./labels";
import { issues, pullRequests, server, session } from "./runtime";
import { ListRow, PageBody, PageText, Toolbar, useWorkspaceTheme } from "./WorkspaceUi";

type ActivityTab = "pullRequests" | "issues" | "usage";
type ListingState = "open" | "closed" | "all";
export type ActivityDetail =
  | { readonly kind: "pullRequests"; readonly entry: PullRequestListEntry }
  | { readonly kind: "issues"; readonly entry: IssueListEntry };

export function WorkspaceActivity({
  tab,
  environmentId,
  detail,
  setDetail,
}: {
  readonly tab: ActivityTab;
  readonly environmentId: EnvironmentId;
  readonly detail: ActivityDetail | null;
  readonly setDetail: (detail: ActivityDetail | null) => void;
}) {
  const config = useAtomValue(server.configValueAtom(environmentId));
  const auth = useAtomValue(session.sessionStateAtom(environmentId));
  const supportsTab =
    tab === "usage"
      ? !sessionDeniesScope(auth, AuthDiagnosticsReadScope)
      : config?.environment.capabilities[tab] === true;

  if (detail?.kind === tab) {
    return detail.kind === "issues" ? (
      <IssueDetail
        environmentId={environmentId}
        entry={detail.entry}
        back={() => setDetail(null)}
      />
    ) : (
      <PullDetail environmentId={environmentId} entry={detail.entry} back={() => setDetail(null)} />
    );
  }
  return (
    <>
      <Toolbar title={text[tab]} />
      {config === undefined || config === null ? (
        <PageBody>
          <PageText muted>{text.loading}</PageText>
        </PageBody>
      ) : !supportsTab ? (
        <PageBody>
          <PageText muted>{text.unavailable}</PageText>
        </PageBody>
      ) : tab === "usage" ? (
        <Usage environmentId={environmentId} />
      ) : (
        <ActivityList key={tab} tab={tab} environmentId={environmentId} setDetail={setDetail} />
      )}
    </>
  );
}

function ActivityList({
  tab,
  environmentId,
  setDetail,
}: {
  readonly tab: Exclude<ActivityTab, "usage">;
  readonly environmentId: EnvironmentId;
  readonly setDetail: (detail: ActivityDetail) => void;
}) {
  const [state, setState] = useState<ListingState>("open");
  const theme = useWorkspaceTheme();
  return (
    <PageBody>
      <EnvironmentListCard color={theme["--color-grouped-card"]}>
        {(["open", "closed", "all"] as const).map((value) => (
          <ListRow
            key={value}
            title={text[value]}
            selected={state === value}
            onPress={() => setState(value)}
          />
        ))}
      </EnvironmentListCard>
      {tab === "issues" ? (
        <IssueRows
          environmentId={environmentId}
          state={state}
          select={(entry) => setDetail({ kind: "issues", entry })}
        />
      ) : (
        <PullRows
          environmentId={environmentId}
          state={state}
          select={(entry) => setDetail({ kind: "pullRequests", entry })}
        />
      )}
    </PageBody>
  );
}

function IssueRows({
  environmentId,
  state,
  select,
}: {
  readonly environmentId: EnvironmentId;
  readonly state: ListingState;
  readonly select: (entry: IssueListEntry) => void;
}) {
  const result = useAtomValue(issues.list({ environmentId, input: { state, limit: 25 } }));
  const rows = AsyncResult.getOrElse(result, () => null);
  const theme = useWorkspaceTheme();
  return (
    <>
      <ReadFeedback
        result={result}
        empty={rows?.entries.length === 0 ? text.noIssues : undefined}
      />
      {rows?.trackers.map((tracker) =>
        tracker.configured || !tracker.detail ? null : (
          <PageText key={tracker.host} muted>
            {tracker.detail}
          </PageText>
        ),
      )}
      {rows?.errors.map((entry) => (
        <PageText key={entry.projectId} error>
          {entry.message}
        </PageText>
      ))}
      {!!rows?.entries.length && (
        <EnvironmentListCard color={theme["--color-grouped-card"]}>
          {rows.entries.map((entry) => (
            <ListRow
              key={`${entry.host}:${entry.scope}:${entry.key}`}
              title={entry.title}
              detail={`${entry.displayKey} · ${entry.projectTitle}`}
              onPress={() => select(entry)}
            />
          ))}
        </EnvironmentListCard>
      )}
    </>
  );
}

function PullRows({
  environmentId,
  state,
  select,
}: {
  readonly environmentId: EnvironmentId;
  readonly state: ListingState;
  readonly select: (entry: PullRequestListEntry) => void;
}) {
  const result = useAtomValue(pullRequests.list({ environmentId, input: { state, limit: 25 } }));
  const rows = AsyncResult.getOrElse(result, () => null);
  const theme = useWorkspaceTheme();
  return (
    <>
      <ReadFeedback
        result={result}
        empty={rows?.entries.length === 0 ? text.noPullRequests : undefined}
      />
      {rows?.providers.map((provider) =>
        provider.configured || !provider.detail ? null : (
          <PageText key={provider.host} muted>
            {provider.detail}
          </PageText>
        ),
      )}
      {rows?.errors.map((entry) => (
        <PageText key={entry.projectId} error>
          {entry.message}
        </PageText>
      ))}
      {!!rows?.entries.length && (
        <EnvironmentListCard color={theme["--color-grouped-card"]}>
          {rows.entries.map((entry) => (
            <ListRow
              key={`${entry.host}:${entry.repository}:${entry.number}`}
              title={entry.title}
              detail={`#${entry.number} · ${entry.repository}`}
              onPress={() => select(entry)}
            />
          ))}
        </EnvironmentListCard>
      )}
    </>
  );
}

function IssueDetail({
  environmentId,
  entry,
  back,
}: {
  readonly environmentId: EnvironmentId;
  readonly entry: IssueListEntry;
  readonly back: () => void;
}) {
  const { projectId, tracker, host, scope, key } = entry;
  const result = useAtomValue(
    issues.detail({ environmentId, input: { projectId, tracker, host, scope, key } }),
  );
  const issue = AsyncResult.getOrElse(result, () => null);
  return (
    <>
      <Toolbar title={entry.displayKey} back={back} />
      <PageBody>
        <PageText>{entry.title}</PageText>
        <PageText muted>{entry.projectTitle}</PageText>
        <ReadFeedback result={result} />
        {issue?.body ? <PageText>{issue.body}</PageText> : null}
        <OpenSource url={entry.url} />
        {!!issue?.comments.length && <PageText muted>{text.comments}</PageText>}
        {issue?.comments.map((comment) => (
          <PageText key={comment.id}>{comment.body}</PageText>
        ))}
      </PageBody>
    </>
  );
}

function PullDetail({
  environmentId,
  entry,
  back,
}: {
  readonly environmentId: EnvironmentId;
  readonly entry: PullRequestListEntry;
  readonly back: () => void;
}) {
  const { projectId, host, repository, number } = entry;
  const result = useAtomValue(
    pullRequests.detail({ environmentId, input: { projectId, host, repository, number } }),
  );
  const pull = AsyncResult.getOrElse(result, () => null);
  return (
    <>
      <Toolbar title={`#${entry.number}`} back={back} />
      <PageBody>
        <PageText>{entry.title}</PageText>
        <PageText muted>{entry.repository}</PageText>
        <PageText muted>
          {entry.headBranch} → {entry.baseBranch}
        </PageText>
        <ReadFeedback result={result} />
        {pull?.body ? <PageText>{pull.body}</PageText> : null}
        <OpenSource url={entry.url} />
      </PageBody>
    </>
  );
}

export function OpenSource({
  url,
  label = text.openInBrowser,
}: {
  readonly url: string;
  readonly label?: string;
}) {
  const [failed, setFailed] = useState(false);
  if (!/^https?:\/\//i.test(url)) return null;
  return (
    <>
      <ListRow
        title={label}
        onPress={() => {
          setFailed(false);
          void Linking.openURL(url).catch(() => setFailed(true));
        }}
      />
      {failed && <PageText error>{text.commandFailed}</PageText>}
    </>
  );
}

function Usage({ environmentId }: { readonly environmentId: EnvironmentId }) {
  const [range, setRange] = useState(() => ({ days: 30, window: makeWindow(30) }));
  const result = useAtomValue(server.usageSummary({ environmentId, input: range.window }));
  const summary = AsyncResult.getOrElse(result, () => null);
  const merged = summary
    ? mergeUsage([{ environmentId, label: "", summary }], USAGE_CONTRACT_VERSION)
    : null;
  const theme = useWorkspaceTheme();
  return (
    <PageBody>
      <EnvironmentListCard color={theme["--color-grouped-card"]}>
        <ListRow
          title={text.last7Days}
          selected={range.days === 7}
          onPress={() => setRange({ days: 7, window: makeWindow(7) })}
        />
        <ListRow
          title={text.last30Days}
          selected={range.days === 30}
          onPress={() => setRange({ days: 30, window: makeWindow(30) })}
        />
      </EnvironmentListCard>
      <ReadFeedback result={result} empty={merged?.records === 0 ? text.noUsage : undefined} />
      {merged && merged.records > 0 && (
        <>
          <View style={styles.totals}>
            {merged.costQuality.unpricedShare < 1 && (
              <PageText>
                {text.cost} · {formatUsd(merged.costUsd)}
              </PageText>
            )}
            <PageText>
              {text.tokens} · {formatTokens(merged.totalTokens)}
            </PageText>
          </View>
          {merged.costQuality.unpricedShare > 0 && <PageText muted>{text.partialUsage}</PageText>}
          {merged.providers.map((provider) => (
            <View key={provider.provider} style={styles.provider}>
              <Text style={{ color: theme["--color-foreground"] }}>{provider.provider}</Text>
              <PageText muted>{formatTokens(provider.totalTokens)}</PageText>
            </View>
          ))}
        </>
      )}
    </PageBody>
  );
}

function ReadFeedback({
  result,
  empty,
}: {
  readonly result: AsyncResult.AsyncResult<unknown, unknown>;
  readonly empty?: string | undefined;
}) {
  if (result._tag === "Failure") return <PageText error>{text.unableToLoad}</PageText>;
  if (result._tag === "Initial") return <ActivityIndicator accessibilityLabel={text.loading} />;
  return empty ? <PageText muted>{empty}</PageText> : null;
}

const styles = StyleSheet.create({
  totals: { flexDirection: "row", flexWrap: "wrap", gap: 16 },
  provider: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
    gap: 12,
  },
});
