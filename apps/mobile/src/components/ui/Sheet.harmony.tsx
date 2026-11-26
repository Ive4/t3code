import { useGT } from "gt-react-native";
import { useState } from "react";

import { InspectorCloseContext } from "../../features/layout/inspector-bar-store";
import { formSheetDetents } from "../../native/sheet-surface";
import { AppBar } from "./AppBar";
import { IconButton } from "./IconButton";
import { PaneSheet } from "./PaneSheet.harmony";
import { RoutedFormSheetContext } from "./RoutedFormSheetContext";
import type { SheetProps } from "./Sheet.types";

export type { SheetProps } from "./Sheet.types";

export function Sheet(props: SheetProps) {
  const gt = useGT();
  const [open, setOpen] = useState(true);

  return (
    <PaneSheet
      isOpen={open}
      detents={formSheetDetents(0.5, 0.9)}
      preventNativeDismiss={props.dismissDisabled}
      onDismiss={props.onClose}
      onNativeDismiss={props.onClose}
    >
      <RoutedFormSheetContext value={false}>
        <InspectorCloseContext value={null}>
          <AppBar
            sheet
            title={props.title}
            hideBottomBorder
            leading={
              <IconButton
                icon="xmark"
                accessibilityLabel={gt("Close {title}", { title: props.title })}
                disabled={props.dismissDisabled}
                onPress={() => setOpen(false)}
              />
            }
          />
        </InspectorCloseContext>
        {props.children}
      </RoutedFormSheetContext>
    </PaneSheet>
  );
}
