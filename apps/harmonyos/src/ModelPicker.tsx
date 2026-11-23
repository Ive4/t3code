import { resolveProvidersForCwd } from "@t3tools/client-runtime/providerSkills";
import {
  isManagedDriverAllowed,
  isProviderAvailable,
  resolveProjectProviderInstanceEnabled,
  type ModelSelection,
  type OrchestrationProjectShell,
  type ServerConfig,
} from "@t3tools/contracts";
import { Button, Modal, Pressable, ScrollView, StyleSheet, Text, View } from "react-native";

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
  labels: { back: string; selectModel: string; noModels: string };
  onClose: () => void;
  onSelect: (selection: ModelSelection) => void;
}) {
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
      <View style={styles.content}>
        <Button title={labels.back} onPress={onClose} />
        <Text accessibilityRole="header" style={styles.title}>
          {labels.selectModel}
        </Text>
        <ScrollView>
          {groups.length === 0 && <Text style={styles.name}>{labels.noModels}</Text>}
          {groups.map(({ provider, models }) => (
            <View key={provider.instanceId} style={styles.group}>
              <Text accessibilityRole="header" style={styles.name}>
                {provider.displayName ?? provider.instanceId}
              </Text>
              {models.map((model) => {
                const checked =
                  provider.instanceId === selection?.instanceId && model.slug === selection.model;
                return (
                  <Pressable
                    key={model.slug}
                    accessibilityRole="radio"
                    accessibilityState={{ checked }}
                    onPress={() =>
                      onSelect(
                        checked
                          ? selection
                          : { instanceId: provider.instanceId, model: model.slug },
                      )
                    }
                    style={[styles.option, checked && styles.selected]}
                  >
                    <Text style={styles.name}>{model.name}</Text>
                  </Pressable>
                );
              })}
            </View>
          ))}
        </ScrollView>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  content: { flex: 1, gap: 12, padding: 20, paddingTop: 44, backgroundColor: "#fff" },
  title: { color: "#171717", fontSize: 26, fontWeight: "600" },
  group: { gap: 6, marginBottom: 14 },
  name: { color: "#171717", fontSize: 16 },
  option: { padding: 12, borderWidth: 1, borderColor: "#8b8b8b", borderRadius: 8 },
  selected: { backgroundColor: "#def0fa", borderColor: "#16658d" },
});
