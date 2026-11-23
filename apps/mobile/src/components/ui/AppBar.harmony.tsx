import { useGT } from "gt-react-native";
import { use, useRef, useState } from "react";
import { Keyboard, Modal, Pressable, ScrollView, View, type TextInputInstance } from "react-native";

import { InspectorCloseContext } from "../../features/layout/inspector-bar-store";
import { useAdaptiveWorkspaceLayout } from "../../features/layout/adaptive-workspace-context";
import { useSidebarToggle } from "../../features/layout/useSidebarToggle";
import { NativeStackScreenOptions } from "../../native/StackHeader";
import { AppActivityIndicator } from "./AppActivityIndicator";
import type { AppBarMenu, AppBarMenuItem, AppBarProps } from "./AppBar.types";
import { AppText } from "./AppText";
import { Button } from "./Button";
import { IconButton } from "./IconButton";
import { ListActionRow } from "./ListActionRow";
import { RoutedFormSheetContext } from "./RoutedFormSheetContext";
import { SearchField } from "./SearchField";
import { useToolbarLayout } from "./useToolbarLayout";

const iconTint = "accent-header-foreground";

export function AppBar(props: AppBarProps) {
  const gt = useGT();
  const { layout } = useAdaptiveWorkspaceLayout();
  const sidebarToggle = useSidebarToggle();
  const closeInspector = use(InspectorCloseContext);
  const inFormSheet = use(RoutedFormSheetContext);
  const { height, paddingTop, paddingBottom } = useToolbarLayout(props.sheet || inFormSheet);
  const [searchOpen, setSearchOpen] = useState(false);
  const [menu, setMenu] = useState<AppBarMenu | null>(null);
  const inputRef = useRef<TextInputInstance>(null);
  const search = props.search;
  const inlineSearch = search?.mode === "inline";
  const searching = search && (inlineSearch || (search.active ?? searchOpen));
  const searchLabel = search?.accessibilityLabel ?? search?.placeholder ?? "";
  const back =
    props.onBack ?? (layout.usesSplitView ? props.backInSplitView?.onPress : props.onBackToList);
  const closeLabel = props.closeAccessibilityLabel ?? gt("Close");
  const closeSearch = () => {
    if (search?.active === undefined) {
      search?.onChangeText("");
      setSearchOpen(false);
      Keyboard.dismiss();
    }
    search?.onClose?.();
  };

  return (
    <>
      {props.embedded || props.sheet ? null : (
        <NativeStackScreenOptions
          options={{
            headerShown: false,
            title: props.title,
            ...(props.guardBack ? { gestureEnabled: false } : {}),
          }}
        />
      )}
      <View
        className="border-b border-header-border bg-header px-2"
        style={{
          paddingTop,
          paddingBottom,
          borderBottomWidth: props.hideBottomBorder ? 0 : undefined,
        }}
      >
        <View className="flex-row items-center gap-1" style={{ minHeight: height }}>
          {searching && !inlineSearch ? (
            <IconButton
              icon="arrow.left"
              accessibilityLabel={gt("Close search")}
              onPress={closeSearch}
            />
          ) : props.onClose ? (
            <IconButton icon="xmark" accessibilityLabel={closeLabel} onPress={props.onClose} />
          ) : back ? (
            <IconButton icon="arrow.left" accessibilityLabel={gt("Navigate up")} onPress={back} />
          ) : (
            (props.leading ??
            (sidebarToggle && !props.sheet ? <IconButton {...sidebarToggle} /> : null))
          )}
          {searching ? (
            <SearchField
              inputRef={inputRef}
              autoFocus={!inlineSearch}
              accessibilityLabel={searchLabel}
              clearAccessibilityLabel={search.clearAccessibilityLabel ?? gt("Clear search")}
              placeholder={search.placeholder}
              value={search.value}
              onChangeText={search.onChangeText}
            />
          ) : (
            <View className="min-w-0 flex-1">
              {props.titleContent ?? (
                <AppText
                  className="text-lg font-t3-semibold text-header-foreground"
                  numberOfLines={1}
                >
                  {props.title}
                </AppText>
              )}
              {props.subtitle ? (
                <AppText className="text-sm text-foreground-muted" numberOfLines={1}>
                  {props.subtitle}
                </AppText>
              ) : null}
            </View>
          )}
          {search && !searching ? (
            <IconButton
              icon="magnifyingglass"
              accessibilityLabel={searchLabel}
              onPress={() => {
                setSearchOpen(true);
                search.onOpen?.();
              }}
            />
          ) : null}
          {props.actions?.map(({ loading, ...action }) =>
            loading ? (
              <View
                key={action.accessibilityLabel}
                accessible
                accessibilityLabel={action.accessibilityLabel}
                accessibilityState={{ busy: true }}
                className="size-12 items-center justify-center"
              >
                <AppActivityIndicator color={action.tintColor} />
              </View>
            ) : (
              <IconButton
                key={action.accessibilityLabel}
                {...action}
                tintColorClassName={iconTint}
              />
            ),
          )}
          {props.refresh ? <IconButton {...props.refresh} icon="arrow.clockwise" /> : null}
          {props.menus?.map((item) => (
            <IconButton
              key={item.title}
              icon={item.icon}
              accessibilityLabel={item.title}
              onPress={() => setMenu(item)}
            />
          ))}
          {props.trailing}
          {props.confirm ? <Button {...props.confirm} tone="text" /> : null}
          {closeInspector ? (
            <IconButton
              icon="xmark"
              accessibilityLabel={gt("Close inspector")}
              onPress={closeInspector}
            />
          ) : null}
        </View>
      </View>
      {menu ? (
        <Modal transparent animationType="fade" onRequestClose={() => setMenu(null)}>
          <View className="flex-1 justify-center p-6">
            <Pressable
              className="absolute inset-0 bg-black/40"
              accessibilityRole="button"
              accessibilityLabel={gt("Close")}
              onPress={() => setMenu(null)}
            />
            <ScrollView className="max-h-[75%] grow-0 rounded-2xl bg-grouped-card">
              {menu.items.map((item) => (
                <MenuItem key={item.id} item={item} onSelect={() => setMenu(null)} />
              ))}
            </ScrollView>
          </View>
        </Modal>
      ) : null}
    </>
  );
}

function MenuItem({
  item,
  onSelect,
}: {
  readonly item: AppBarMenuItem;
  readonly onSelect: () => void;
}) {
  if ("items" in item) {
    return (
      <>
        {item.title ? (
          <AppText className="px-4 py-2 text-sm text-foreground-muted">{item.title}</AppText>
        ) : null}
        {item.items.map((child) => (
          <MenuItem key={child.id} item={child} onSelect={onSelect} />
        ))}
      </>
    );
  }

  return (
    <ListActionRow
      label={item.title}
      description={item.subtitle}
      disabled={item.disabled}
      tone={item.destructive ? "danger" : "default"}
      onPress={() => {
        onSelect();
        item.onPress();
      }}
    />
  );
}

export type {
  AppBarAction,
  AppBarConfirm,
  AppBarMenu,
  AppBarMenuItem,
  AppBarProps,
  AppBarSearch,
} from "./AppBar.types";
