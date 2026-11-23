import { useAtomValue } from "@effect/atom-react";
import type { EnvironmentId, ThreadId } from "@t3tools/contracts";
import { AsyncResult } from "effect/reactivity";
import { StyleSheet, TextInput, View } from "react-native";

import { EnvironmentListCard } from "../../mobile/src/features/connection/EnvironmentListContent";
import { text } from "./labels";
import { orchestration, server } from "./runtime";
import { OpenSource } from "./WorkspaceActivity";
import { ListRow, PageBody, PageText, Toolbar, useWorkspaceTheme } from "./WorkspaceUi";

export type Appearance = "systemTheme" | "lightTheme" | "darkTheme";
export type SettingsPage = "settings" | "appearance" | "about" | "archive" | "providers";

export function WorkspaceSettings({
  page,
  appearance,
  onAppearance,
  onPage,
  environmentId,
  environmentCount,
  onEnvironments,
  openThread,
}: {
  readonly page: SettingsPage;
  readonly appearance: Appearance;
  readonly onAppearance: (value: Appearance) => void;
  readonly onPage: (page: SettingsPage) => void;
  readonly environmentId: EnvironmentId;
  readonly environmentCount: number;
  readonly onEnvironments: () => void;
  readonly openThread: (threadId: ThreadId) => void;
}) {
  const theme = useWorkspaceTheme();
  const card = theme["--color-grouped-card"];
  const goBack = () => onPage("settings");
  return (
    <>
      <Toolbar title={text[page]} {...(page !== "settings" && { back: goBack })} />
      <PageBody>
        {page === "appearance" ? (
          <EnvironmentListCard color={card}>
            {(["systemTheme", "lightTheme", "darkTheme"] as const).map((value) => (
              <ListRow
                key={value}
                title={text[value]}
                selected={appearance === value}
                onPress={() => onAppearance(value)}
              />
            ))}
          </EnvironmentListCard>
        ) : page === "archive" ? (
          <Archive environmentId={environmentId} openThread={openThread} />
        ) : page === "providers" ? (
          <Providers environmentId={environmentId} />
        ) : page === "about" ? (
          <EnvironmentListCard color={card}>
            <View style={styles.about}>
              <PageText>T3 Code</PageText>
              <PageText muted>HarmonyOS</PageText>
            </View>
            <OpenSource url="https://t3.codes/legal" label={text.legal} />
          </EnvironmentListCard>
        ) : (
          <>
            <PageText muted>{text.connections}</PageText>
            <EnvironmentListCard color={card}>
              <ListRow
                title={text.environments}
                detail={String(environmentCount)}
                onPress={onEnvironments}
              />
            </EnvironmentListCard>
            <EnvironmentListCard color={card}>
              <ListRow title={text.appearance} onPress={() => onPage("appearance")} />
              <ListRow title={text.providers} onPress={() => onPage("providers")} />
              <ListRow title={text.archive} onPress={() => onPage("archive")} />
              <ListRow title={text.about} onPress={() => onPage("about")} />
            </EnvironmentListCard>
          </>
        )}
      </PageBody>
    </>
  );
}

function Providers({ environmentId }: { readonly environmentId: EnvironmentId }) {
  const config = useAtomValue(server.configValueAtom(environmentId));
  const theme = useWorkspaceTheme();
  if (config === null) return <PageText muted>{text.loading}</PageText>;
  if (config.providers.length === 0) return <PageText muted>{text.noProviders}</PageText>;
  return (
    <EnvironmentListCard color={theme["--color-grouped-card"]}>
      {config.providers.map((provider) => (
        <View
          key={provider.instanceId}
          style={[styles.provider, { borderBottomColor: theme["--color-border-subtle"] }]}
        >
          <PageText>{provider.displayName ?? provider.instanceId}</PageText>
          <PageText muted>{provider.installed ? text.installed : text.notInstalled}</PageText>
          {provider.models.length > 0 && (
            <PageText muted>{provider.models.map((model) => model.name).join(" · ")}</PageText>
          )}
        </View>
      ))}
    </EnvironmentListCard>
  );
}

function Archive({
  environmentId,
  openThread,
}: {
  readonly environmentId: EnvironmentId;
  readonly openThread: (threadId: ThreadId) => void;
}) {
  const state = useAtomValue(orchestration.archivedShellSnapshot({ environmentId, input: {} }));
  const snapshot = AsyncResult.getOrElse(state, () => null);
  const archived = snapshot?.threads ?? [];
  const theme = useWorkspaceTheme();
  if (state._tag === "Failure") return <PageText error>{text.unableToLoad}</PageText>;
  if (snapshot === null) return <PageText muted>{text.loading}</PageText>;
  if (archived.length === 0) return <PageText muted>{text.noArchivedThreads}</PageText>;
  return (
    <EnvironmentListCard color={theme["--color-grouped-card"]}>
      {archived.map((thread) => (
        <ListRow key={thread.id} title={thread.title} onPress={() => openThread(thread.id)} />
      ))}
    </EnvironmentListCard>
  );
}

export function SearchField({
  value,
  onChangeText,
}: {
  readonly value: string;
  readonly onChangeText: (value: string) => void;
}) {
  const theme = useWorkspaceTheme();
  return (
    <TextInput
      accessibilityLabel={text.searchThreads}
      autoCorrect={false}
      onChangeText={onChangeText}
      placeholder={text.searchThreads}
      placeholderTextColor={theme["--color-placeholder"]}
      returnKeyType="search"
      value={value}
      style={[
        styles.search,
        {
          color: theme["--color-foreground"],
          backgroundColor: theme["--color-grouped-card"],
          borderColor: theme["--color-border-subtle"],
        },
      ]}
    />
  );
}

const styles = StyleSheet.create({
  about: { padding: 16, gap: 3 },
  provider: { padding: 16, gap: 3, borderBottomWidth: StyleSheet.hairlineWidth },
  search: {
    marginHorizontal: 16,
    marginVertical: 6,
    minHeight: 44,
    paddingHorizontal: 16,
    borderRadius: 20,
    borderWidth: 1,
  },
});
