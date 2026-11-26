import { T, useGT } from "gt-react-native";
import type { EnvironmentId } from "@t3tools/contracts";
import type { ComponentProps } from "react";
import { View, type ViewProps } from "react-native";

import { SymbolView } from "../../components/ui/AppSymbol";
import { AppText as Text } from "../../components/ui/AppText";
import { ContentStatus } from "../../components/ui/ContentBand";
import { useConnectionsReady } from "../../state/workspace";
import { ConnectionEnvironmentRow } from "./ConnectionEnvironmentRow";
import { EnvironmentListCard } from "./EnvironmentListContent";

type EnvironmentRowProps = ComponentProps<typeof ConnectionEnvironmentRow>;

function GroupedCard(props: ViewProps) {
  return <View {...props} className="bg-grouped-card" />;
}

export function LocalEnvironmentList({
  environments,
  expandedId,
  onToggle,
  ...rowActions
}: Pick<
  EnvironmentRowProps,
  "onReconnect" | "onRemove" | "onSetEnabled" | "onUpdate" | "opensDetails"
> & {
  readonly environments: ReadonlyArray<EnvironmentRowProps["environment"]>;
  readonly expandedId: EnvironmentId | null;
  readonly onToggle: (environmentId: EnvironmentId) => void;
}) {
  const gt = useGT();
  const connectionsReady = useConnectionsReady();
  if (environments.length === 0) {
    if (!connectionsReady) {
      return <ContentStatus loading detail={gt("Loading environments")} />;
    }
    return (
      <View
        collapsable={false}
        className="items-center gap-3 rounded-[24px] bg-grouped-card px-6 py-8"
      >
        <View className="h-12 w-12 items-center justify-center rounded-[16px] bg-subtle">
          <SymbolView
            name="point.3.connected.trianglepath.dotted"
            size={20}
            tintColorClassName="accent-icon-muted"
            type="monochrome"
          />
        </View>
        <Text className="text-center text-sm leading-normal text-foreground-muted">
          <T>No environments connected yet.</T>
          {"\n"}
          <T>
            Tap <Text className="font-t3-bold text-foreground">+</Text> to add one.
          </T>
        </Text>
      </View>
    );
  }

  return (
    <EnvironmentListCard ViewComponent={GroupedCard}>
      {environments.map((environment) => (
        <View key={environment.environmentId} collapsable={false}>
          <ConnectionEnvironmentRow
            environment={environment}
            expanded={expandedId === environment.environmentId}
            onToggle={() => onToggle(environment.environmentId)}
            {...rowActions}
          />
        </View>
      ))}
    </EnvironmentListCard>
  );
}
