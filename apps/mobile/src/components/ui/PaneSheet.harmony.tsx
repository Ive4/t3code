import { useGT } from "gt-react-native";
import { useEffect, useEffectEvent, useRef, useState } from "react";
import { Modal, Pressable, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";

import { ModalOverlayScope, OverlayPortalHost } from "./OverlayPortal";
import type { PaneSheetProps } from "./PaneSheet.types";
export type { PaneSheetProps } from "./PaneSheet.types";

export function PaneSheet(props: PaneSheetProps) {
  const gt = useGT();
  const insets = useSafeAreaInsets();
  const [userDismissed, setUserDismissed] = useState(false);
  const [expanded, setExpanded] = useState(false);
  const visible = props.isOpen && !userDismissed;
  const wasVisible = useRef(false);
  const onDismissed = useEffectEvent(() => {
    if (userDismissed) props.onNativeDismiss();
    else props.onDismiss();
  });
  // Harmony's Modal has no onDismiss callback. With native animation disabled the modal is
  // removed in the same commit, before the dismiss callback can open another screen.
  // oxlint-disable-next-line t3code/no-unreasoned-state-sync -- reports dismissal after the native modal has been removed from the tree
  useEffect(() => {
    const didDismiss = wasVisible.current && !visible;
    wasVisible.current = visible;
    if (didDismiss) onDismissed();
  }, [visible]);

  if (!props.isOpen && userDismissed) setUserDismissed(false);
  if (!visible && expanded) setExpanded(false);
  if (!visible) return null;

  const requestClose = () => {
    if (!props.preventNativeDismiss) setUserDismissed(true);
  };
  const compactDetent = props.detents[0] ?? 1;
  const expandedDetent = props.detents.at(-1) ?? compactDetent;
  const height = expanded ? expandedDetent : compactDetent;

  return (
    <ModalOverlayScope onRequestClose={requestClose}>
      {(onRequestClose) => (
        <Modal
          transparent
          animationType="none"
          statusBarTranslucent
          navigationBarTranslucent
          onRequestClose={onRequestClose}
        >
          <View
            className="flex-1 justify-end"
            style={{ paddingTop: insets.top, paddingLeft: insets.left, paddingRight: insets.right }}
          >
            <Pressable
              accessible={false}
              importantForAccessibility="no-hide-descendants"
              disabled={props.preventNativeDismiss}
              onPress={requestClose}
              className="absolute inset-0 bg-backdrop"
            />
            <View
              accessibilityViewIsModal
              onAccessibilityEscape={requestClose}
              className="overflow-hidden rounded-t-[28px] bg-sheet-solid"
              style={{ height: `${height * 100}%` }}
            >
              {expandedDetent > compactDetent ? (
                <Pressable
                  accessibilityRole="button"
                  accessibilityLabel={expanded ? gt("Show less") : gt("Show more")}
                  accessibilityState={{ expanded }}
                  onPress={() => setExpanded(!expanded)}
                  className="h-12 items-center justify-center bg-header"
                >
                  <View className="h-1 w-8 rounded-full bg-header-foreground/40" />
                </Pressable>
              ) : null}
              <View className="flex-1">{props.children}</View>
            </View>
            <OverlayPortalHost />
          </View>
        </Modal>
      )}
    </ModalOverlayScope>
  );
}
