import { useNavigation } from "@react-navigation/native";
import { useGT } from "gt-react-native";
import { AppBar } from "../../../components/ui/AppBar";
import { appBarMenuItemsFromActions } from "../../../components/ui/menuActionItems";
import { WorkspaceConnectionTitle } from "../../home/WorkspaceConnectionTitle";
import type { SharedSlotTab } from "./navigation-tab-order";
import { SharedSlotTitle } from "./SharedSlotTitle";
import { useWorkspaceListSearch } from "./useWorkspaceListSearch";
import type { PullRequestFilterMenu } from "../../pull-requests/PullRequestListFilters";
import { openSettings } from "../../settings/settings-navigation";

export function ListSearchToolbar(props: {
  readonly tab: SharedSlotTab;
  readonly filters?: PullRequestFilterMenu | null;
  readonly showConnectionStatus?: boolean;
  readonly onRequestVisibility?: () => void;
}) {
  const gt = useGT();
  const navigation = useNavigation();
  const { filters, tab: section } = props;
  const search = useWorkspaceListSearch(
    section,
    section === "issues" ? gt("Search issues") : gt("Search pull requests"),
    props.onRequestVisibility,
  );
  const title = <SharedSlotTitle tab={section} />;
  return (
    <AppBar
      title="T3 Code"
      titleContent={
        props.showConnectionStatus === false ? (
          title
        ) : (
          <WorkspaceConnectionTitle
            grow
            onPress={() => openSettings(navigation, "SettingsEnvironments")}
            brand={title}
          />
        )
      }
      search={search}
      menus={
        filters
          ? [
              {
                title: section === "issues" ? gt("Filter issues") : gt("Filter pull requests"),
                icon: filters.customized
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle",
                items: appBarMenuItemsFromActions(filters.actions, filters.onSelect),
              },
            ]
          : undefined
      }
    />
  );
}
