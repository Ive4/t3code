import { useGT, useMessages } from "gt-react-native";
import { Pressable, View } from "react-native";
import Animated, { cubicBezier, useReducedMotion } from "react-native-reanimated";
import { useSafeAreaInsets } from "react-native-safe-area-context";

import { AppText } from "../../../components/ui/AppText";
import { SymbolView } from "../../../components/ui/AppSymbol";
import { cn } from "../../../lib/cn";
import { selectedNavigationTab, visibleNavigationTabs } from "./navigation-tab-order";
import {
  NAVIGATION_TAB_ICONS,
  useHiddenNavigationTabs,
  useNavigationTabOrder,
  WORKSPACE_TAB_LABELS,
} from "./navigation-tabs";
import { useSelectWorkspaceTab } from "./useSelectWorkspaceTab";
import { useWorkspaceTabs } from "./WorkspaceTabsContext";

const PRESS_EASING = cubicBezier(0.23, 1, 0.32, 1);

export function WorkspaceTabDock(_props: { readonly placement: "column" | "window" }) {
  const gt = useGT();
  const m = useMessages();
  const workspace = useWorkspaceTabs();
  const selectTab = useSelectWorkspaceTab();
  const order = useNavigationTabOrder();
  const hidden = useHiddenNavigationTabs();
  const reduceMotion = useReducedMotion();
  const { bottom } = useSafeAreaInsets();
  if (!workspace) return null;

  const selected = selectedNavigationTab(
    order,
    workspace.state.selectedTab,
    workspace.settingsOpen,
    hidden,
  );
  const tabs = [...visibleNavigationTabs(order, hidden), "settings"] as const;

  return (
    <View
      className="flex-row border-t border-header-border bg-header px-2"
      style={{ paddingBottom: bottom }}
    >
      {tabs.map((tab) => {
        const label = tab === "settings" ? gt("Settings") : m(WORKSPACE_TAB_LABELS[tab]);
        const active = tab === selected;
        return (
          <Pressable
            key={tab}
            accessibilityRole="tab"
            accessibilityLabel={label}
            accessibilityState={{ selected: active }}
            onPress={() => selectTab(tab)}
            className="min-h-14 min-w-0 flex-1 justify-center px-1"
          >
            {({ pressed }) => (
              <Animated.View
                className="items-center gap-1"
                style={{
                  opacity: pressed ? 0.75 : 1,
                  transform: [{ scale: pressed && !reduceMotion ? 0.97 : 1 }],
                  transitionProperty: ["opacity", "transform"],
                  transitionDuration: reduceMotion ? 0 : 120,
                  transitionTimingFunction: PRESS_EASING,
                }}
              >
                <SymbolView
                  name={tab === "settings" ? "gearshape" : NAVIGATION_TAB_ICONS[tab]}
                  size={22}
                  tintColorClassName={active ? "accent-primary" : "accent-header-foreground"}
                />
                <AppText
                  className={cn("text-xs", active ? "text-primary" : "text-header-foreground")}
                  numberOfLines={1}
                >
                  {label}
                </AppText>
              </Animated.View>
            )}
          </Pressable>
        );
      })}
    </View>
  );
}
