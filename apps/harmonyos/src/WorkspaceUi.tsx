import { createContext, useContext, type ReactNode } from "react";
import { ActivityIndicator, Pressable, ScrollView, StyleSheet, Text, View } from "react-native";
import { DEFAULT_MOBILE_THEME_ID, getMobileThemeVariables } from "../../mobile/src/lib/mobileTheme";
import { androidWorkspaceNavigationColors } from "../../mobile/src/features/layout/workspace/android-workspace-navigation-colors";
import { text } from "./labels";

export const WorkspaceTheme = createContext(
  getMobileThemeVariables(DEFAULT_MOBILE_THEME_ID, "light"),
);
export const useWorkspaceTheme = () => useContext(WorkspaceTheme);

export const WORKSPACE_TABS = ["threads", "pullRequests", "issues", "usage", "settings"] as const;
export type WorkspaceTab = (typeof WORKSPACE_TABS)[number];

export function WorkspaceTabs({
  selected,
  onSelect,
}: {
  readonly selected: WorkspaceTab;
  readonly onSelect: (tab: WorkspaceTab) => void;
}) {
  const theme = useWorkspaceTheme();
  const colors = androidWorkspaceNavigationColors(theme, false);
  return (
    <View style={[styles.tabs, { backgroundColor: colors.containerColor }]}>
      {WORKSPACE_TABS.map((tab) => {
        const active = selected === tab;
        return (
          <Pressable
            key={tab}
            accessibilityRole="tab"
            accessibilityState={{ selected: active }}
            onPress={() => onSelect(tab)}
            style={[styles.tab, active && { backgroundColor: colors.indicatorColor }]}
          >
            <Text
              numberOfLines={1}
              style={[
                styles.tabLabel,
                { color: active ? colors.selectedColor : colors.unselectedColor },
              ]}
            >
              {text[tab]}
            </Text>
          </Pressable>
        );
      })}
    </View>
  );
}

export function Toolbar({
  title,
  back,
  children,
}: {
  readonly title: string;
  readonly back?: () => void;
  readonly children?: ReactNode;
}) {
  const theme = useWorkspaceTheme();
  return (
    <View style={styles.toolbar}>
      {back && <ToolbarAction label={text.back} glyph="‹" onPress={back} />}
      <Text
        accessibilityRole="header"
        numberOfLines={1}
        style={[styles.title, { color: theme["--color-header-foreground"] }]}
      >
        {title}
      </Text>
      {children}
    </View>
  );
}

export function ToolbarAction({
  label,
  glyph,
  disabled,
  busy,
  onPress,
}: {
  readonly label: string;
  readonly glyph: string;
  readonly disabled?: boolean;
  readonly busy?: boolean;
  readonly onPress: () => void;
}) {
  const theme = useWorkspaceTheme();
  const color = theme["--color-header-foreground"];
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={label}
      accessibilityState={{ busy: !!busy }}
      disabled={disabled || busy}
      onPress={onPress}
      style={[styles.tool, disabled && !busy && { opacity: 0.38 }]}
    >
      {busy ? (
        <ActivityIndicator accessibilityLabel={label} color={color} />
      ) : (
        <Text style={[styles.toolGlyph, { color }]}>{glyph}</Text>
      )}
    </Pressable>
  );
}

export function PageBody({ children }: { readonly children: ReactNode }) {
  return (
    <ScrollView
      style={styles.pageBody}
      contentContainerStyle={styles.pageContent}
      keyboardShouldPersistTaps="handled"
    >
      {children}
    </ScrollView>
  );
}

export function PageText({
  children,
  muted,
  error,
}: {
  readonly children: ReactNode;
  readonly muted?: boolean;
  readonly error?: boolean;
}) {
  const theme = useWorkspaceTheme();
  return (
    <Text
      accessibilityRole={error ? "alert" : undefined}
      selectable
      style={[
        styles.text,
        {
          color:
            theme[
              error
                ? "--color-danger-foreground"
                : muted
                  ? "--color-foreground-muted"
                  : "--color-foreground"
            ],
        },
      ]}
    >
      {children}
    </Text>
  );
}

export function ListRow({
  title,
  detail,
  selected,
  onPress,
}: {
  readonly title: string;
  readonly detail?: string;
  readonly selected?: boolean;
  readonly onPress: () => void;
}) {
  const theme = useWorkspaceTheme();
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityState={selected === undefined ? undefined : { selected }}
      onPress={onPress}
      style={({ pressed }) => [
        styles.listRow,
        { borderBottomColor: theme["--color-border-subtle"] },
        (pressed || selected) && { backgroundColor: theme["--color-card-alt"] },
      ]}
    >
      <View style={styles.label}>
        <Text style={[styles.text, { color: theme["--color-foreground"] }]} numberOfLines={2}>
          {title}
        </Text>
        {detail && (
          <Text style={{ color: theme["--color-foreground-muted"] }} numberOfLines={1}>
            {detail}
          </Text>
        )}
      </View>
      <Text
        accessibilityElementsHidden
        style={[styles.endGlyph, { color: theme["--color-foreground-muted"] }]}
      >
        {selected ? "✓" : "›"}
      </Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  toolbar: {
    minHeight: 56,
    paddingHorizontal: 12,
    flexDirection: "row",
    alignItems: "center",
    gap: 8,
  },
  title: { flex: 1, paddingStart: 4, fontSize: 20, fontWeight: "600" },
  tool: { alignItems: "center", justifyContent: "center", width: 44, height: 44 },
  toolGlyph: { fontSize: 24 },
  pageBody: { flex: 1 },
  pageContent: { gap: 14, paddingHorizontal: 16, paddingTop: 8, paddingBottom: 32 },
  text: { fontSize: 15, lineHeight: 21 },
  listRow: {
    flexDirection: "row",
    alignItems: "center",
    minHeight: 52,
    paddingHorizontal: 16,
    paddingVertical: 10,
    borderBottomWidth: StyleSheet.hairlineWidth,
    gap: 10,
  },
  label: { flex: 1, minWidth: 0, gap: 2 },
  endGlyph: { fontSize: 18 },
  tabs: { flexDirection: "row", gap: 2, paddingHorizontal: 10, paddingTop: 6, paddingBottom: 16 },
  tab: {
    minWidth: 0,
    flexBasis: 0,
    flexGrow: 1,
    justifyContent: "center",
    alignItems: "center",
    minHeight: 48,
    borderRadius: 24,
    paddingHorizontal: 2,
  },
  tabLabel: { fontSize: 12, fontWeight: "600" },
});
