import { useGT } from "gt-react-native";
import { Pressable } from "react-native";

import { CompactBrandTitle } from "../../../components/CompactBrandTitle";
import { AppBar } from "../../../components/ui/AppBar";
import { WorkspaceConnectionTitle } from "../../home/WorkspaceConnectionTitle";
import {
  workspaceListFilterIcon,
  type WorkspaceListHeaderProps,
} from "./WorkspaceListHeader.types";
import { useWorkspaceCompose } from "./useWorkspaceCompose";

export function WorkspaceListHeader(props: WorkspaceListHeaderProps) {
  const gt = useGT();
  const compose = useWorkspaceCompose();
  return (
    <AppBar
      embedded
      title={props.accessibilityLabel}
      titleContent={
        <Pressable
          accessibilityRole="button"
          accessibilityLabel={gt("Environments")}
          hitSlop={8}
          onPress={props.onOpenEnvironments}
          className="min-h-11 justify-center"
        >
          <WorkspaceConnectionTitle
            brand={<CompactBrandTitle accessibilityLabel={props.accessibilityLabel} fit />}
          />
        </Pressable>
      }
      actions={
        compose
          ? [
              {
                accessibilityLabel: compose.label,
                icon: "square.and.pencil",
                onPress: compose.onPress,
              },
            ]
          : undefined
      }
      search={props.search}
      menus={[
        {
          title: gt("Filter threads"),
          icon: workspaceListFilterIcon(props.filter.customized),
          items: props.filter.items,
        },
      ]}
    />
  );
}
