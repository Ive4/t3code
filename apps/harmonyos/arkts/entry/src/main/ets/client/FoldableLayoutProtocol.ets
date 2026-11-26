export type WorkspaceLayoutMode = 'compact' | 'split';

export type FoldPosture = 'flat' | 'half-folded' | 'folded' | 'unknown';

export interface WorkspaceWindowMetrics {
  widthVp: number;
  heightVp: number;
  foldPosture: FoldPosture;
}

export const SPLIT_BREAKPOINT_VP = 600;
export const MIN_SIDEBAR_WIDTH_VP = 280;
export const MAX_SIDEBAR_WIDTH_VP = 360;
const SIDEBAR_WIDTH_RATIO = 0.34;

export function resolveWorkspaceLayoutMode(metrics: WorkspaceWindowMetrics): WorkspaceLayoutMode {
  const widthVp = Number.isFinite(metrics.widthVp) ? metrics.widthVp : 0;
  if (widthVp <= 0) {
    return 'compact';
  }
  if (metrics.foldPosture === 'folded') {
    return 'compact';
  }
  if (widthVp >= SPLIT_BREAKPOINT_VP) {
    return 'split';
  }
  return 'compact';
}

export function resolveSidebarWidthVp(widthVp: number): number {
  if (!Number.isFinite(widthVp) || widthVp <= 0) {
    return MIN_SIDEBAR_WIDTH_VP;
  }
  const scaled = Math.round(widthVp * SIDEBAR_WIDTH_RATIO);
  if (scaled < MIN_SIDEBAR_WIDTH_VP) {
    return MIN_SIDEBAR_WIDTH_VP;
  }
  if (scaled > MAX_SIDEBAR_WIDTH_VP) {
    return MAX_SIDEBAR_WIDTH_VP;
  }
  return scaled;
}
