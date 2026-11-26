export interface StoreAppUpdateClient {
  checkForUpdate(): Promise<boolean>;
}

// oxlint-disable-next-line t3code/no-hookless-use-function -- The .harmony.ts implementation uses hooks to read AppGallery availability.
export function useStoreAppUpdateClient(): StoreAppUpdateClient | null {
  return null;
}
