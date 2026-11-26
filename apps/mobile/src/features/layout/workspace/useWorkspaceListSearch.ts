import { useNavigation } from "@react-navigation/native";
import { Keyboard } from "react-native";

import type { AppBarSearch } from "../../../components/ui/AppBar.types";
import { useHardwareBack } from "../../../lib/backHandler";
import { useHardwareKeyboardCommand } from "../../keyboard/hardwareKeyboardCommands";
import type { SharedSlotTab } from "./navigation-tab-order";
import { useWorkspaceTabs } from "./WorkspaceTabsContext";

export function useWorkspaceListSearch(
  section: SharedSlotTab | "settings",
  placeholder: string,
  onRequestVisibility?: () => void,
): AppBarSearch {
  const navigation = useNavigation();
  const { state, dispatch, getScrollOffset, isTabActive, cancelSearch } = useWorkspaceTabs()!;
  const tab = state.tabs[section];
  const active = tab.searchMode !== "resting";
  const hasSelectedList = () => section === "settings" || isTabActive(section);
  const listOnTop = () => {
    const navigationState = navigation.getState();
    return (
      navigationState?.routes[navigationState.index]?.name ===
      (section === "settings" ? "Settings" : "Home")
    );
  };
  const openSearch = () => {
    onRequestVisibility?.();
    dispatch({ type: "scroll", tab: section, offset: getScrollOffset(section) });
    dispatch({ type: "search", tab: section });
  };
  const closeSearch = () => {
    Keyboard.dismiss();
    cancelSearch(section);
  };
  useHardwareKeyboardCommand("focusSearch", () => {
    if (!hasSelectedList() || (!onRequestVisibility && !listOnTop())) return false;
    openSearch();
    return true;
  });
  useHardwareBack(active, () => {
    // A frozen list can still be mounted under another route or tab.
    if (!listOnTop() || !hasSelectedList()) return false;
    if (Keyboard.isVisible()) Keyboard.dismiss();
    else closeSearch();
    return true;
  });
  return {
    value: tab.query,
    onChangeText: (query) => dispatch({ type: "query", tab: section, query }),
    placeholder,
    active,
    onOpen: openSearch,
    onClose: closeSearch,
  };
}
