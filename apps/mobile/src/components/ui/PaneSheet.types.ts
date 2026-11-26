import type { ReactNode } from "react";

export interface PaneSheetProps {
  readonly children: ReactNode;
  readonly isOpen: boolean;
  readonly detents: number[];
  readonly prefersHorizontalBars?: boolean;
  readonly preventNativeDismiss?: boolean;
  readonly onDismiss: () => void;
  readonly onNativeDismiss: () => void;
}
