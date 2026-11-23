import { resolveProvidersForCwd } from "@t3tools/client-runtime/providerSkills";
import {
  isManagedDriverAllowed,
  isProviderAvailable,
  resolveProjectProviderInstanceEnabled,
  type ModelSelection,
  type OrchestrationProjectShell,
  type ServerConfig,
} from "@t3tools/contracts";
import { Modal, StyleSheet, View } from "react-native";
import { EnvironmentListCard } from "../../mobile/src/features/connection/EnvironmentListContent";
import { ListRow, PageBody, PageText, Toolbar, useWorkspaceTheme } from "./WorkspaceUi";

export function ModelPicker({
  config,
  project,
  selection,
  labels,
  onClose,
  onSelect,
}: {
  config: ServerConfig | null;
  project: OrchestrationProjectShell;
  selection: ModelSelection | null;
  labels: { selectModel: string; noModels: string };
  onClose: () => void;
  onSelect: (selection: ModelSelection) => void;
}) {
  const theme = useWorkspaceTheme();
  const groups = config
    ? resolveProvidersForCwd(config.providers, project.workspaceRoot).flatMap((provider) => {
        if (
          !provider.installed ||
          provider.auth.status === "unauthenticated" ||
          !isProviderAvailable(provider) ||
          !isManagedDriverAllowed(config.managedPolicy, provider.driver) ||
          !resolveProjectProviderInstanceEnabled(config.settings, project.id, provider.instanceId)
        ) {
          return [];
        }
        const preferences = config.settings.providerModelPreferences?.[provider.instanceId];
        const hidden = new Set(preferences?.hiddenModels);
        const order = new Map(preferences?.modelOrder?.map((slug, index) => [slug, index]));
        const models = provider.models
          .filter((model) => model.isCustom || !hidden.has(model.slug))
          .sort(
            (left, right) =>
              (order.get(left.slug) ?? Number.MAX_SAFE_INTEGER) -
              (order.get(right.slug) ?? Number.MAX_SAFE_INTEGER),
          );
        return models.length > 0 ? [{ provider, models }] : [];
      })
    : [];

  return (
    <Modal onRequestClose={onClose}>
      <View style={[styles.content, { backgroundColor: theme["--color-sheet-solid"] }]}>
        <Toolbar title={labels.selectModel} back={onClose} />
        <PageBody>
          {groups.length === 0 && <PageText muted>{labels.noModels}</PageText>}
          {groups.map(({ provider, models }) => (
            <View key={provider.instanceId} style={styles.group}>
              <PageText muted>{provider.displayName ?? provider.instanceId}</PageText>
              <EnvironmentListCard color={theme["--color-grouped-card"]}>
                {models.map((model) => {
                  const checked =
                    provider.instanceId === selection?.instanceId && model.slug === selection.model;
                  return (
                    <ListRow
                      key={model.slug}
                      title={model.name}
                      selected={checked}
                      onPress={() =>
                        onSelect(
                          checked
                            ? selection
                            : { instanceId: provider.instanceId, model: model.slug },
                        )
                      }
                    />
                  );
                })}
              </EnvironmentListCard>
            </View>
          ))}
        </PageBody>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  content: { flex: 1, paddingTop: 40 },
  group: { gap: 6 },
});
